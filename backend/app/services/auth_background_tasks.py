"""Фоновые задачи auth (отдельная DB-сессия, не блокируют ответ login/register)."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def refresh_scan_credits_for_user(user_id: int) -> None:
    from app.core.database import SessionLocal
    from app.services.ai_scan_credits_service import AiScanCreditsService

    db = SessionLocal()
    try:
        AiScanCreditsService(db).refresh_user(user_id)
    except Exception as e:
        logger.warning("refresh_scan_credits_for_user %s: %s", user_id, e)
    finally:
        db.close()
