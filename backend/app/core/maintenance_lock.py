"""Распределённая блокировка фоновых задач API (один worker при нескольких репликах)."""
from __future__ import annotations

import logging

from app.core.config import settings

logger = logging.getLogger(__name__)

MAINTENANCE_LOCK_KEY = "han:api:maintenance_lock"


def try_acquire_maintenance_lock(redis, ttl_seconds: int = 55) -> bool:
    """
    True — этот процесс может выполнить maintenance в текущем цикле.
    Без Redis (dev) — всегда True.
    """
    if not getattr(settings, "REDIS_ENABLED", True):
        return True
    try:
        acquired = redis.set(
            MAINTENANCE_LOCK_KEY,
            "1",
            nx=True,
            ex=ttl_seconds,
        )
        return bool(acquired)
    except Exception as e:
        logger.warning("Maintenance lock unavailable, running anyway: %s", e)
        return True
