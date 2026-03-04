import asyncio
import logging
from typing import Dict, Any
from app.agent.agent_core import AgentCore

# Structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
)
logger = logging.getLogger(__name__)


def _get_or_create_event_loop() -> asyncio.AbstractEventLoop:
    """Get the current event loop or create a fresh one for the worker process."""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_closed():
            raise RuntimeError("Loop is closed")
        return loop
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        return loop


def _send_fallback_sync(workflow_id: str, error_msg: str):
    """
    Best-effort synchronous fallback Telegram notification.
    Uses httpx.post (sync) to avoid touching an already-errored event loop.
    """
    try:
        import httpx
        import os

        bot_token = os.getenv("TELEGRAM_BOT_TOKEN", "")
        chat_id = os.getenv("TELEGRAM_CHAT_ID", "")
        if not bot_token or not chat_id:
            logger.warning("[Fallback] Missing Telegram credentials — cannot alert.")
            return

        message = (
            f"🔴 *AGENT SYSTEM FAILURE*\n\n"
            f"📌 *Workflow:* {workflow_id}\n"
            f"❌ *Error:* {error_msg[:300]}\n\n"
            f"👉 Check worker logs immediately."
        )
        httpx.post(
            f"https://api.telegram.org/bot{bot_token}/sendMessage",
            json={"chat_id": chat_id, "text": message, "parse_mode": "Markdown"},
            timeout=10.0
        )
        logger.info("[Fallback] Emergency Telegram alert sent.")
    except Exception as e:
        logger.critical(f"[Fallback] Emergency Telegram also failed: {e}")


def analyze_incident_task(incident_data: Dict[str, Any]):
    """
    Synchronous RQ task entry point.
    Wraps the async AgentCore in a fresh or existing event loop.
    Returns structured result dict (never raises — RQ retry is handled separately).
    """
    workflow_id = incident_data.get("workflow_id", "Unknown")
    logger.info(f"[Worker] Task received | workflow={workflow_id}")

    # Handle nest_asyncio for environments where a loop is already running
    loop = _get_or_create_event_loop()
    if loop.is_running():
        try:
            import nest_asyncio
            nest_asyncio.apply()
        except ImportError:
            logger.warning("[Worker] nest_asyncio not installed — may encounter loop conflicts")

    try:
        agent = AgentCore(incident_data)
        result = loop.run_until_complete(agent.analyze())
        logger.info(
            f"[Worker] Analysis complete | workflow={workflow_id} | "
            f"status={result.get('status')} | "
            f"duration={result.get('duration_ms')}ms | "
            f"iterations={result.get('iterations')}"
        )
        return result

    except Exception as critical_err:
        logger.critical(
            f"[Worker] CRITICAL FAILURE | workflow={workflow_id} | error={critical_err}",
            exc_info=True
        )
        # Best-effort fallback — synchronous, cannot raise
        _send_fallback_sync(workflow_id, str(critical_err))
        return {"status": "critical_error", "message": str(critical_err)}


if __name__ == "__main__":
    from rq import Worker, Queue
    from redis import Redis
    from app.core.config import settings

    redis_conn = Redis.from_url(settings.REDIS_URL)
    queue = Queue("incident_triage", connection=redis_conn)
    worker = Worker([queue], connection=redis_conn)
    worker.work(with_scheduler=False)
