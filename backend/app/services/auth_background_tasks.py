"""Фоновые задачи auth (отдельная DB-сессия, не блокируют ответ login/register)."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def refresh_scan_credits_for_user(user_id: int) -> None:
    """No-op: kitchen AI-scan credits are retired (HanWe messenger)."""
    logger.debug("skip scan credits refresh for user %s (kitchen retired)", user_id)
