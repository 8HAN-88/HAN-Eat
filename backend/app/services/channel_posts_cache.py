"""Redis cache for GET /channels/:id/posts."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def invalidate_channel_posts_cache(channel_id: int) -> None:
    """Drop every first-page cache variant for this channel."""
    try:
        from app.core.redis_client import REDIS_IS_STUB, get_redis

        if REDIS_IS_STUB:
            return
        redis = get_redis()
        pattern = f"channel_posts:{int(channel_id)}:*"
        keys: list = []
        scan_iter = getattr(redis, "scan_iter", None)
        if callable(scan_iter):
            keys = list(scan_iter(match=pattern, count=200))
        else:
            keys_fn = getattr(redis, "keys", None)
            if callable(keys_fn):
                found = keys_fn(pattern)
                if found:
                    keys = list(found)
        if keys:
            redis.delete(*keys)
    except Exception as exc:
        logger.warning(
            "Failed to invalidate channel posts cache for %s: %s",
            channel_id,
            exc,
        )
