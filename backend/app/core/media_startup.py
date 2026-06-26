"""Проверка готовности S3/CDN для медиа."""
from __future__ import annotations

import logging
import shutil

from app.core.config import settings

logger = logging.getLogger(__name__)


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def video_queue_depth() -> int | None:
    try:
        from app.core.redis_client import redis_client
        from app.services.video_queue_service import VideoQueueService

        return int(redis_client.llen(VideoQueueService.QUEUE_KEY))
    except Exception:
        return None


def video_worker_heartbeat_age_seconds() -> int | None:
    try:
        from app.services.video_queue_service import VideoQueueService

        return VideoQueueService.worker_heartbeat_age_seconds()
    except Exception:
        return None


def media_upload_mode() -> str:
    """s3 — прямая загрузка в объектное хранилище; api — через диск VPS."""
    if not settings.S3_ACCESS_KEY or not settings.S3_SECRET_KEY:
        return "api"
    try:
        from app.services.media_service import MediaService

        return "api" if MediaService().uses_api_upload else "s3"
    except Exception:
        return "api"


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
        if media_upload_mode() == "s3" and not ffmpeg_available():
            issues.append(
                "FFmpeg не установлен — видео сохраняются в S3, но без транскодинга 720p/480p"
            )
        if getattr(settings, "REDIS_ENABLED", True):
            age = video_worker_heartbeat_age_seconds()
            if age is None:
                issues.append("Video worker heartbeat отсутствует — транскодинг видео может не работать")
            elif age > 120:
                issues.append(f"Video worker heartbeat устарел ({age}s) — транскодинг видео может зависнуть")
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
