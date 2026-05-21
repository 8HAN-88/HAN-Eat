"""Проверки инфраструктуры (БД, Redis, Firebase) для readiness."""
from __future__ import annotations

import logging
import os

from sqlalchemy import text

from app.core.config import settings
from app.core.database import engine
from app.core.redis_client import get_redis

logger = logging.getLogger(__name__)


def check_database() -> tuple[bool, str | None]:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, None
    except Exception as e:
        return False, f"Database unreachable: {e}"


def check_redis() -> tuple[bool, str | None]:
    if not getattr(settings, "REDIS_ENABLED", True):
        return True, None
    client = get_redis()
    try:
        client.ping()
        return True, None
    except Exception as e:
        return False, f"Redis unreachable: {e}"


def collect_firebase_issues() -> list[str]:
    issues: list[str] = []
    if not settings.FIREBASE_ENABLED:
        return issues

    if not os.getenv("FIREBASE_CREDENTIALS_JSON") and not (
        settings.FIREBASE_CREDENTIALS_PATH
        and os.path.exists(settings.FIREBASE_CREDENTIALS_PATH)
    ):
        issues.append(
            "FIREBASE_ENABLED=true, но нет FIREBASE_CREDENTIALS_JSON "
            "или FIREBASE_CREDENTIALS_PATH"
        )
        return issues

    try:
        from app.services.push_service import get_push_service

        push = get_push_service()
        if not push.enabled:
            issues.append("Firebase Admin SDK не инициализирован — push не работает")
    except Exception as e:
        issues.append(f"Firebase init error: {e}")

    return issues


def collect_infrastructure_issues() -> list[str]:
    issues: list[str] = []
    db_ok, db_err = check_database()
    if not db_ok and db_err:
        issues.append(db_err)

    if getattr(settings, "REDIS_ENABLED", True):
        redis_ok, redis_err = check_redis()
        if not redis_ok and redis_err:
            issues.append(redis_err)
    issues.extend(collect_firebase_issues())
    return issues


def infrastructure_status() -> dict:
    db_ok, db_err = check_database()
    redis_ok, redis_err = (True, None)
    if getattr(settings, "REDIS_ENABLED", True):
        redis_ok, redis_err = check_redis()
    firebase_issues = collect_firebase_issues()
    push_enabled = False
    try:
        from app.services.push_service import get_push_service

        push_enabled = get_push_service().enabled
    except Exception:
        pass

    return {
        "database": {"ok": db_ok, "error": db_err},
        "redis": {
            "enabled": getattr(settings, "REDIS_ENABLED", True),
            "ok": redis_ok,
            "error": redis_err,
        },
        "firebase": {
            "enabled": settings.FIREBASE_ENABLED,
            "push_ready": push_enabled,
            "issues": firebase_issues,
        },
    }
