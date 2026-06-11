"""Инвалидация кэша статистики профиля (Redis)."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def invalidate_user_stats_cache(user_ids: list[int]) -> None:
    if not user_ids:
        return
    try:
        from app.core.redis_client import get_redis

        redis_client = get_redis()
        for uid in user_ids:
            if uid:
                redis_client.delete(f"user_stats:{uid}")
    except Exception as e:
        logger.warning("Failed to invalidate user stats cache: %s", e)
