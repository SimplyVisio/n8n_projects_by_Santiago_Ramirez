"""
Redis-backed Circuit Breaker — Multi-Process Safe, Restart-Resilient.

State lives in Redis → consistent across processes/containers.

IMPORTANT design decision on TTL strategy:
  - failure counter TTL = recovery_timeout × 3
    (survives short Redis restarts without the circuit getting stuck OPEN)
  - opened_at key TTL = recovery_timeout × 5
    (long enough to survive restarts; auto-cleans on circuit recovery)
  - first_failure_at key = Unix wall-clock timestamp (NOT monotonic)
    (persists across restarts — monotonic would be meaningless after restart)

Why NOT persist in DB?
  Acceptable trade-off for most systems. If Redis restarts, circuit resets to
  CLOSED, meaning the next batch of calls will fail and re-open the circuit
  within seconds. This is the correct "fail-safe-open" posture.
  DB persistence would be warranted only if you need forensic auditability
  of circuit state history, which belongs in the reasoning logs instead.

States: CLOSED → OPEN → HALF_OPEN → CLOSED
"""

import time
import logging
from enum import Enum
from typing import Callable, Any

import redis as sync_redis

logger = logging.getLogger(__name__)

_PREFIX = "circuit_breaker"


class CircuitState(Enum):
    CLOSED    = "CLOSED"
    OPEN      = "OPEN"
    HALF_OPEN = "HALF_OPEN"


class CircuitBreakerOpen(Exception):
    """Raised when a call is attempted while the circuit is OPEN."""
    pass


class RedisCircuitBreaker:
    """
    Redis-backed circuit breaker.

    Redis keys:
      {prefix}:{name}:failures        — atomic INCR counter
      {prefix}:{name}:opened_at       — Wall-clock epoch when circuit tripped
      {prefix}:{name}:first_fail_at   — Wall-clock epoch of first failure
                                        (used for optional future max_lifetime logic)
    """

    def __init__(
        self,
        redis_url: str,
        name: str = "openai",
        failure_threshold: int = 3,
        recovery_timeout: float = 60.0,
    ):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout

        self._redis = sync_redis.from_url(redis_url, decode_responses=True)
        self._key_failures   = f"{_PREFIX}:{name}:failures"
        self._key_opened_at  = f"{_PREFIX}:{name}:opened_at"
        self._key_first_fail = f"{_PREFIX}:{name}:first_fail_at"

    # ------------------------------------------------------------------ #
    #   Internal readers                                                   #
    # ------------------------------------------------------------------ #

    def _failure_count(self) -> int:
        val = self._redis.get(self._key_failures)
        return int(val) if val else 0

    def _opened_at(self) -> float:
        """
        Wall-clock timestamp (time.time()) of when the circuit opened.
        Uses time.time() — NOT time.monotonic() — so it survives Redis restarts.
        """
        val = self._redis.get(self._key_opened_at)
        return float(val) if val else 0.0

    # ------------------------------------------------------------------ #
    #   State machine                                                      #
    # ------------------------------------------------------------------ #

    @property
    def state(self) -> CircuitState:
        failures = self._failure_count()
        if failures < self.failure_threshold:
            return CircuitState.CLOSED

        opened_at = self._opened_at()
        # Use wall-clock diff so state survives process restarts
        elapsed = time.time() - opened_at
        if elapsed >= self.recovery_timeout:
            logger.info(
                f"[CB:{self.name}] OPEN → HALF_OPEN "
                f"(recovery probe after {elapsed:.0f}s)"
            )
            return CircuitState.HALF_OPEN

        return CircuitState.OPEN

    # ------------------------------------------------------------------ #
    #   Transitions                                                        #
    # ------------------------------------------------------------------ #

    def _record_success(self) -> None:
        """Reset all circuit state → CLOSED."""
        self._redis.delete(
            self._key_failures,
            self._key_opened_at,
            self._key_first_fail
        )
        logger.info(f"[CB:{self.name}] Call succeeded → CLOSED (keys deleted)")

    def _record_failure(self) -> None:
        """
        Atomically increment failure counter.
        On first failure: record first_fail_at (wall-clock, persistent).
        On threshold: record opened_at and log OPEN transition.
        """
        now_wall = time.time()
        pipe = self._redis.pipeline()

        # Atomic INCR + sliding TTL on the counter
        # TTL = recovery_timeout × 3 so the counter survives short Redis restarts
        # without getting stuck. If Redis is down for > 3× recovery, it resets (safe).
        pipe.incr(self._key_failures)
        pipe.expire(self._key_failures, int(self.recovery_timeout * 3))
        _, new_count = pipe.execute()

        logger.warning(
            f"[CB:{self.name}] Failure #{new_count}/{self.failure_threshold}"
        )

        # Record first_fail_at on first failure (NX = only if not exists)
        self._redis.set(
            self._key_first_fail,
            str(now_wall),
            nx=True,                               # don't overwrite
            ex=int(self.recovery_timeout * 6)
        )

        if new_count >= self.failure_threshold:
            # Record wall-clock open time, long enough to survive restarts
            self._redis.set(
                self._key_opened_at,
                str(now_wall),
                ex=int(self.recovery_timeout * 5)
            )
            logger.error(
                f"[CB:{self.name}] Threshold reached → OPEN. "
                f"Will probe after {self.recovery_timeout}s."
            )

    # ------------------------------------------------------------------ #
    #   Public interface                                                   #
    # ------------------------------------------------------------------ #

    async def call(self, func: Callable, *args, **kwargs) -> Any:
        """Execute an async callable through the circuit breaker."""
        current = self.state
        if current == CircuitState.OPEN:
            count = self._failure_count()
            raise CircuitBreakerOpen(
                f"[CB:{self.name}] OPEN — {count}/{self.failure_threshold} failures. "
                f"Recovery probe in {self.recovery_timeout}s."
            )
        try:
            result = await func(*args, **kwargs)
            self._record_success()
            return result
        except Exception:
            self._record_failure()
            raise

    def get_status(self) -> dict:
        """Return current breaker status — useful for /ready endpoint."""
        return {
            "name": self.name,
            "state": self.state.value,
            "failure_count": self._failure_count(),
            "threshold": self.failure_threshold,
            "recovery_timeout_s": self.recovery_timeout,
        }


def build_openai_circuit_breaker(redis_url: str) -> RedisCircuitBreaker:
    """Factory — produces the shared breaker instance for OpenAI calls."""
    return RedisCircuitBreaker(
        redis_url=redis_url,
        name="openai",
        failure_threshold=3,
        recovery_timeout=60.0
    )
