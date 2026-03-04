"""
Full rewrite of reasoning_loop.py.
Integrates:
  - Redis-backed circuit breaker (multi-process safe)
  - Exponential backoff with jitter
  - Prometheus metrics (iterations, duration, tool calls, outcomes, OAI latency)
  - Dual tool-loop detection
  - Structured log format
"""

import json
import logging
import time
import uuid
from typing import Dict, Any, Optional

from openai import AsyncOpenAI, APITimeoutError, APIError

from app.core.config import settings
from app.core.circuit_breaker import RedisCircuitBreaker, CircuitBreakerOpen, build_openai_circuit_breaker
from app.core.retry import with_exponential_backoff
from app.core.metrics import (
    AGENT_ITERATIONS,
    AGENT_PROCESSING_SECONDS,
    OPENAI_CALL_DURATION,
    OPENAI_RETRIES,
    CIRCUIT_BREAKER_STATE,
    record_tool_call,
    record_agent_outcome,
    record_openai_error,
)
from app.agent.tool_registry import TOOL_DEFINITIONS, TOOL_MAPPING
from app.db.models import AgentReasoningLog
from app.db.session import AsyncSessionLocal

logger = logging.getLogger(__name__)

# One Redis-backed breaker shared by all agent instances in this process.
# Across processes, state lives in Redis — no per-process divergence.
_circuit_breaker: Optional[RedisCircuitBreaker] = None


def _get_circuit_breaker() -> RedisCircuitBreaker:
    global _circuit_breaker
    if _circuit_breaker is None:
        _circuit_breaker = build_openai_circuit_breaker(settings.REDIS_URL)
    return _circuit_breaker


class ReasoningLoop:
    def __init__(self, incident_data: Dict[str, Any]):
        self.client = AsyncOpenAI(
            api_key=settings.OPENAI_API_KEY,
            timeout=settings.OPENAI_TIMEOUT
        )
        self.max_iterations = settings.AGENT_MAX_ITERATIONS
        self.incident_data = incident_data
        self.tool_call_history: list[tuple] = []
        self.current_incident_id: Optional[uuid.UUID] = None
        self.fingerprint: Optional[str] = None
        self.start_time = time.monotonic()
        self._cb = _get_circuit_breaker()

        self.messages = [
            {
                "role": "system",
                "content": (
                    "You are a Senior DevOps Incident Intelligence Specialist. "
                    "Analyze raw JSON errors, fingerprint them, check memory, "
                    "and provide structured root cause analysis and fixes.\n\n"
                    "MANDATORY EXECUTION ORDER:\n"
                    "1. generate_fingerprint — always first.\n"
                    "2. check_redis_memory — hot memory before cold.\n"
                    "3. If Redis miss → query_incident_stats_sql then cache_in_redis.\n"
                    "4. finalize_incident_transactional — atomic DB write (incident + stats).\n"
                    "5. send_telegram_notification — alert the team.\n"
                    "6. finalize_incident_decision — signal end of analysis.\n\n"
                    "You have a strict iteration budget. If you have already sent a notification "
                    "or stored the incident, you MUST call finalize_incident_decision in the next "
                    "step to complete the task. DO NOT procrastinate.\n\n"
                    "NEVER call the same tool with identical arguments more than once. "
                    "NEVER query full tables. Always filter by fingerprint or error_message."
                )
            },
            {
                "role": "user",
                "content": f"New incident from n8n: {json.dumps(incident_data)}"
            }
        ]

    # ------------------------------------------------------------------ #
    #   LLM call — circuit breaker + backoff + metrics                    #
    # ------------------------------------------------------------------ #

    async def _llm_call(self):
        async def _inner():
            t0 = time.monotonic()
            try:
                result = await self.client.chat.completions.create(
                    model=settings.OPENAI_MODEL,
                    messages=self.messages,
                    tools=TOOL_DEFINITIONS,
                    tool_choice="auto"
                )
                OPENAI_CALL_DURATION.observe(time.monotonic() - t0)
                return result
            except APITimeoutError as e:
                record_openai_error("timeout")
                OPENAI_CALL_DURATION.observe(time.monotonic() - t0)
                raise
            except APIError as e:
                record_openai_error("api_error")
                OPENAI_CALL_DURATION.observe(time.monotonic() - t0)
                raise

        # Update CB gauge before the call
        cb_state_map = {"CLOSED": 0, "HALF_OPEN": 1, "OPEN": 2}
        CIRCUIT_BREAKER_STATE.labels(breaker_name="openai").set(
            cb_state_map.get(self._cb.state.value, 0)
        )

        return await self._cb.call(
            with_exponential_backoff,
            _inner,
            max_retries=settings.OPENAI_MAX_RETRIES,
            base_delay=1.5,
            max_delay=15.0,
            retriable_exceptions=(APITimeoutError, APIError)
        )

    # ------------------------------------------------------------------ #
    #   Loop guard                                                         #
    # ------------------------------------------------------------------ #

    def _is_looping(self, call_tuple: tuple) -> bool:
        if self.tool_call_history.count(call_tuple) >= 2:
            logger.warning(f"[LoopGuard] Exact repetition: {call_tuple[0]}")
            return True
        history = self.tool_call_history
        if len(history) >= 4 and history[-2:] == history[-4:-2]:
            logger.warning("[LoopGuard] Alternating cycle A→B→A→B detected")
            return True
        return False

    # ------------------------------------------------------------------ #
    #   Step logger — non-blocking, best-effort                           #
    # ------------------------------------------------------------------ #

    async def _log_step(
        self, iteration: int, thought: str,
        tool_name: str = None, tool_input: Any = None, tool_output: Any = None
    ):
        try:
            async with AsyncSessionLocal() as db:
                log = AgentReasoningLog(
                    incident_id=self.current_incident_id,
                    iteration_number=iteration,
                    thought=(thought or "")[:1000],
                    tool_name=tool_name,
                    tool_input=tool_input if isinstance(tool_input, dict) else None,
                    tool_output=({"result": str(tool_output)[:500]} if tool_output else None)
                )
                db.add(log)
                await db.commit()
        except Exception as e:
            logger.warning(f"[ReasoningLog] Non-critical persistence failure: {e}")

    # ------------------------------------------------------------------ #
    #   Main loop                                                          #
    # ------------------------------------------------------------------ #

    async def execute(self) -> Dict[str, Any]:
        workflow_id = self.incident_data.get("workflow_id", "unknown")
        logger.info(
            f"[ReasoningLoop] START | workflow={workflow_id} | max_iter={self.max_iterations}"
        )

        max_iter = self.max_iterations
        for iteration in range(1, max_iter + 2):  # +1 for regular iterations, +1 for grace loop
            # ── Check for hard limit (exhausted grace iteration) ── #
            if iteration > max_iter + 1:
                break
            
            # ── Grace iteration log ── #
            if iteration > max_iter:
                logger.warning(f"[ReasoningLoop] GRACE ITERATION triggered for finalization.")

            elapsed_ms = int((time.monotonic() - self.start_time) * 1000)
            logger.info(
                f"[ReasoningLoop] iter={iteration}/{max_iter} | "
                f"tool_calls={len(self.tool_call_history)} | elapsed={elapsed_ms}ms"
            )

            # ── LLM call ── #
            try:
                response = await self._llm_call()
            except CircuitBreakerOpen as cbe:
                record_openai_error("circuit_open")
                CIRCUIT_BREAKER_STATE.labels(breaker_name="openai").set(2)
                logger.critical(f"[CircuitBreaker] OPEN — {cbe}")
                record_agent_outcome("circuit_open")
                return {"status": "circuit_open", "message": str(cbe), "iterations": iteration}
            except Exception as e:
                duration = time.monotonic() - self.start_time
                logger.error(f"[ReasoningLoop] LLM failed after retries: {e}")
                record_agent_outcome("error")
                AGENT_PROCESSING_SECONDS.observe(duration)
                return {"status": "error", "message": str(e), "duration_ms": int(duration * 1000)}

            msg = response.choices[0].message
            self.messages.append(msg)

            # ── No tool calls ── #
            if not msg.tool_calls:
                await self._log_step(iteration, msg.content or "Final thought — no tools")
                if iteration == self.max_iterations:
                    duration = time.monotonic() - self.start_time
                    AGENT_ITERATIONS.observe(iteration)
                    record_agent_outcome("max_iterations_reached")
                    AGENT_PROCESSING_SECONDS.observe(duration)
                    return {
                        "status": "max_iterations_reached",
                        "summary": msg.content,
                        "iterations": iteration,
                        "duration_ms": int(duration * 1000)
                    }
                continue

            # ── Process tool calls ── #
            for tool_call in msg.tool_calls:
                tool_name = tool_call.function.name
                try:
                    tool_args = json.loads(tool_call.function.arguments)
                except json.JSONDecodeError:
                    tool_args = {}

                call_tuple = (tool_name, json.dumps(tool_args, sort_keys=True))

                # Loop guard
                if self._is_looping(call_tuple):
                    record_agent_outcome("error")
                    return {
                        "status": "error",
                        "message": "Tool loop detected — aborting.",
                        "last_tool": tool_name,
                        "iterations": iteration
                    }
                self.tool_call_history.append(call_tuple)

                # Terminal tool
                if tool_name == "finalize_incident_decision":
                    duration = time.monotonic() - self.start_time
                    AGENT_ITERATIONS.observe(iteration)
                    AGENT_PROCESSING_SECONDS.observe(duration)
                    record_agent_outcome("success")
                    logger.info(
                        f"[ReasoningLoop] DONE | iter={iteration} | "
                        f"duration={int(duration*1000)}ms | fingerprint={self.fingerprint} | "
                        f"total_tools={len(self.tool_call_history)}"
                    )
                    decision = tool_args.get("decision", {})
                    decision.update({
                        "duration_ms": int(duration * 1000),
                        "iterations": iteration,
                        "tool_calls_total": len(self.tool_call_history),
                        "fingerprint": self.fingerprint
                    })
                    return decision

                # Execute tool — safe helper enforces cardinality
                record_tool_call(tool_name)
                tool_func = TOOL_MAPPING.get(tool_name)
                if not tool_func:
                    tool_result = f"Unknown tool: {tool_name}"
                    logger.warning(f"[ToolRegistry] {tool_result}")
                else:
                    try:
                        tool_result = await tool_func(**tool_args)
                        if tool_name == "generate_fingerprint":
                            self.fingerprint = str(tool_result)
                        elif tool_name == "store_incident_postgres":
                            try:
                                self.current_incident_id = uuid.UUID(str(tool_result))
                            except (ValueError, AttributeError):
                                pass
                    except Exception as tool_err:
                        logger.error(f"[Tool:{tool_name}] {tool_err}")
                        tool_result = f"Error: {str(tool_err)}"

                self.messages.append({
                    "tool_call_id": tool_call.id,
                    "role": "tool",
                    "name": tool_name,
                    "content": str(tool_result)
                })
                await self._log_step(
                    iteration,
                    thought=msg.content or f"Called {tool_name}",
                    tool_name=tool_name,
                    tool_input=tool_args,
                    tool_output=tool_result
                )

        duration = time.monotonic() - self.start_time
        record_agent_outcome("incomplete")
        AGENT_PROCESSING_SECONDS.observe(duration)
        return {
            "status": "incomplete",
            "summary": "Max iterations exhausted.",
            "iterations": self.max_iterations,
            "duration_ms": int(duration * 1000)
        }
