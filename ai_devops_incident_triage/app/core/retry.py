"""
Exponential Backoff Retry Utility.
Wraps async callables with configurable retry logic and jitter.
"""

import asyncio
import random
import logging
from typing import Callable, Any, Tuple, Type

logger = logging.getLogger(__name__)


async def with_exponential_backoff(
    func: Callable,
    *args,
    max_retries: int = 2,
    base_delay: float = 1.0,
    max_delay: float = 15.0,
    retriable_exceptions: Tuple[Type[Exception], ...] = (Exception,),
    **kwargs
) -> Any:
    """
    Execute an async function with exponential backoff on failure.

    Args:
        func: Async callable to execute.
        max_retries: Maximum number of retry attempts.
        base_delay: Starting delay in seconds.
        max_delay: Maximum delay cap.
        retriable_exceptions: Tuple of exceptions that trigger a retry.
    """
    last_exception = None
    for attempt in range(max_retries + 1):
        try:
            return await func(*args, **kwargs)
        except retriable_exceptions as e:
            last_exception = e
            if attempt == max_retries:
                logger.error(
                    f"[Retry] All {max_retries + 1} attempts failed for {func.__name__}. "
                    f"Last error: {e}"
                )
                raise

            # Exponential backoff with jitter to avoid thundering herd
            delay = min(base_delay * (2 ** attempt) + random.uniform(0, 1.0), max_delay)
            logger.warning(
                f"[Retry] Attempt {attempt + 1}/{max_retries + 1} failed: {e}. "
                f"Retrying in {delay:.2f}s..."
            )
            await asyncio.sleep(delay)

    raise last_exception
