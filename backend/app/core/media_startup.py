"""Проверка готовности S3/CDN для медиа."""
from __future__ import annotations

import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


def collect_media_issues() -> list[str]:
    issues: list[str] = []
    if not settings.S3_ACCESS_KEY or not settings.S3_SECRET_KEY:
        issues.append("S3_ACCESS_KEY / S3_SECRET_KEY не заданы — загрузки через API (диск)")
    else:
        try:
            from app.services.media_service import MediaService

            if MediaService().uses_api_upload:
                issues.append(
                    "S3 ключи заданы, но недоступны (InvalidAccessKeyId и т.п.) — загрузки через API"
                )
        except Exception as e:
            issues.append(f"S3 проверка не удалась: {e}")
    if not settings.S3_BUCKET:
        issues.append("S3_BUCKET не задан")
    if settings.APP_ENV == "production":
        if "127.0.0.1" in (settings.API_PUBLIC_BASE_URL or ""):
            issues.append("API_PUBLIC_BASE_URL localhost — публичные URL медиа недоступны извне")
        if settings.CDN_URL.startswith("https://cdn.haneat.com") and not settings.S3_ACCESS_KEY:
            issues.append("CDN_URL задан, но S3 не настроен")
    return issues


def log_media_readiness() -> None:
    issues = collect_media_issues()
    if not issues:
        if settings.S3_ACCESS_KEY:
            logger.info(
                "Media: S3 ready (bucket=%s, cdn=%s)",
                settings.S3_BUCKET,
                settings.CDN_URL,
            )
        else:
            logger.info("Media: mock upload mode (dev)")
        return
    for msg in issues:
        logger.warning("Media: %s", msg)
