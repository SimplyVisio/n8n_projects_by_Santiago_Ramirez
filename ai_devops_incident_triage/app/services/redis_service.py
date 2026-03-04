"""
Redis Memory Service — Sliding TTL with Absolute Lifetime Cap.

TTL Strategy:
  - SLIDING window: every cache hit resets the TTL to REDIS_TTL_SECONDS.
    Active recurring errors stay in hot memory indefinitely while occurring.

  - ABSOLUTE cap: a second key stores the first_stored_at timestamp.
    If wall-clock age exceeds REDIS_MAX_LIFETIME_SECONDS, the context is
    evicted on next get() regardless of how recently it was accessed.

Why this matters:
  Without the absolute cap, a low-frequency error (e.g., every 6 days)
  could survive for months in Redis by just barely refreshing before expiry.
  This would cause the agent to use stale analysis from months ago as if it
  were current context — a subtle but real reasoning quality issue.

Configuration:
  REDIS_TTL_SECONDS          — Sliding window reset on each hit (default 7d)
  REDIS_MAX_LIFETIME_SECONDS — Hard eviction ceiling (default 30d)
    Set to 0 to disable the absolute cap (pure sliding window behaviour).
"""

import time
import json
import logging
from typing import Optional

import redis.asyncio as aioredis

from app.core.config import settings
from app.core.metrics import (
    REDIS_CACHE_HITS,
    REDIS_CACHE_MISSES,
    record_redis_op,
)

logger = logging.getLogger(__name__)

_MEM_PREFIX  = "memory"       # context value
_META_PREFIX = "memory_meta"  # creation metadata (first_stored_at)


class RedisService:
    def __init__(self):
        self.redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        self._max_lifetime = getattr(settings, "REDIS_MAX_LIFETIME_SECONDS", 30 * 86400)

    # ------------------------------------------------------------------ #
    #   Hot-memory read                                                    #
    # ------------------------------------------------------------------ #

    async def get_memory(self, fingerprint: str) -> Optional[str]:
        """
        Fetch context for a fingerprint.

        1. Miss → return None (agent falls through to DB).
        2. Hit + within absolute lifetime → refresh TTL (sliding window) + return.
        3. Hit + exceeded absolute lifetime → evict + return None (force fresh analysis).
        """
        t0 = time.monotonic()
        mem_key  = f"{_MEM_PREFIX}:{fingerprint}"
        meta_key = f"{_META_PREFIX}:{fingerprint}"

        try:
            # Fetch value and metadata in one round-trip
            pipe = self.redis.pipeline()
            pipe.get(mem_key)
            pipe.get(meta_key)
            value, meta_raw = await pipe.execute()
            latency = time.monotonic() - t0
            record_redis_op("get", latency)

            if not value:
                REDIS_CACHE_MISSES.inc()
                logger.debug(f"[Redis] MISS  fp={fingerprint[:12]}… ({latency*1000:.1f}ms)")
                return None

            # Check absolute lifetime cap
            if self._max_lifetime > 0 and meta_raw:
                try:
                    meta = json.loads(meta_raw)
                    age_seconds = time.time() - float(meta.get("first_stored_at", 0))
                    if age_seconds > self._max_lifetime:
                        logger.info(
                            f"[Redis] EVICT fp={fingerprint[:12]}… "
                            f"age={age_seconds/86400:.1f}d > max={self._max_lifetime/86400:.1f}d"
                        )
                        # Evict both keys
                        await self.redis.delete(mem_key, meta_key)
                        REDIS_CACHE_MISSES.inc()
                        return None
                except (ValueError, TypeError, json.JSONDecodeError):
                    pass  # Corrupted metadata — treat as valid hit, will heal on next set

            # Valid hit: refresh sliding TTL
            await self.redis.expire(mem_key, settings.REDIS_TTL_SECONDS)
            REDIS_CACHE_HITS.inc()
            logger.debug(f"[Redis] HIT   fp={fingerprint[:12]}… ({latency*1000:.1f}ms) TTL refreshed")
            return value

        except Exception as e:
            logger.error(f"[Redis] get_memory error: {e}")
            REDIS_CACHE_MISSES.inc()
            return None

    # ------------------------------------------------------------------ #
    #   Hot-memory write                                                   #
    # ------------------------------------------------------------------ #

    async def set_memory(
        self,
        fingerprint: str,
        context: str,
        ttl: Optional[int] = None
    ) -> None:
        """
        Store context with sliding TTL.
        On first write, also stores first_stored_at metadata for absolute cap.
        Metadata TTL = max_lifetime so it self-cleans with the context key.
        """
        ttl = ttl or settings.REDIS_TTL_SECONDS
        mem_key  = f"{_MEM_PREFIX}:{fingerprint}"
        meta_key = f"{_META_PREFIX}:{fingerprint}"

        t0 = time.monotonic()
        try:
            meta = json.dumps({"first_stored_at": time.time()})
            meta_ttl = max(self._max_lifetime, ttl) if self._max_lifetime > 0 else ttl

            pipe = self.redis.pipeline()
            pipe.set(mem_key, context, ex=ttl)
            # NX = only set if not exists — preserves original first_stored_at
            pipe.set(meta_key, meta, ex=meta_ttl, nx=True)
            await pipe.execute()

            latency = time.monotonic() - t0
            record_redis_op("set", latency)
            logger.debug(
                f"[Redis] SET   fp={fingerprint[:12]}… "
                f"ttl={ttl}s max_lifetime={self._max_lifetime}s ({latency*1000:.1f}ms)"
            )
        except Exception as e:
            logger.error(f"[Redis] set_memory error: {e}")

    # ------------------------------------------------------------------ #
    #   Utilities                                                          #
    # ------------------------------------------------------------------ #

    async def ping(self) -> bool:
        """Lightweight connectivity probe for /ready endpoint."""
        try:
            return await self.redis.ping()
        except Exception:
            return False

    async def close(self) -> None:
        await self.redis.aclose()


redis_service = RedisService()
