"""Проверки конфигурации перед production."""
from __future__ import annotations

import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


def collect_production_issues() -> list[str]:
    if settings.APP_ENV != "production":
        return []

    issues: list[str] = []
    if settings.DEBUG:
        issues.append("DEBUG=true в production")
    if not settings.SECRET_KEY or len(settings.SECRET_KEY) < 32:
        issues.append("SECRET_KEY слишком короткий или пустой")
    if "change" in settings.SECRET_KEY.lower() or "dev" in settings.SECRET_KEY.lower():
        issues.append("SECRET_KEY похож на dev-значение")
    if settings.SKIP_GOOGLE_ID_TOKEN_VERIFICATION:
        issues.append("SKIP_GOOGLE_ID_TOKEN_VERIFICATION=true запрещён в production")
    if not settings.GOOGLE_OAUTH_CLIENT_IDS.strip():
        issues.append("GOOGLE_OAUTH_CLIENT_IDS пуст — Google Sign-In небезопасен")
    if "127.0.0.1" in (settings.API_PUBLIC_BASE_URL or ""):
        issues.append("API_PUBLIC_BASE_URL указывает на localhost")
    if not settings.S3_BUCKET:
        issues.append("S3_BUCKET не задан — загрузки медиа через mock")
    if not getattr(settings, "REDIS_ENABLED", True):
        issues.append("REDIS_ENABLED=false в production — realtime/cache/locks/video queue деградируют")
    else:
        try:
            from app.core.redis_client import REDIS_IS_STUB

            if REDIS_IS_STUB:
                issues.append("Redis работает в stub mode — realtime/cache/locks/video queue недоступны")
        except Exception as e:
            issues.append(f"Redis readiness check failed: {e}")
    # Kitchen recipe translator is no longer a production requirement (messenger).
    return issues


def log_production_readiness() -> None:
    issues = collect_production_issues()
    if not issues:
        if settings.APP_ENV == "production":
            logger.info("Production config checks passed")
        return
    for msg in issues:
        logger.error("Production config: %s", msg)
