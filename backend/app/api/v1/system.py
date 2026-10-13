"""Системные эндпоинты: readiness для деплоя."""
from fastapi import APIRouter

from app.core.config import settings
from app.core.infrastructure_startup import (
    collect_infrastructure_issues,
    infrastructure_status,
)
from app.core.media_startup import (
    collect_media_issues,
    ffmpeg_available,
    media_upload_mode,
)
from app.core.payments_startup import collect_payments_issues
from app.core.production_startup import collect_production_issues

router = APIRouter()


def _s3_fully_configured() -> bool:
    if not settings.S3_ACCESS_KEY or not settings.S3_SECRET_KEY:
        return False
    try:
        from app.services.media_service import MediaService

        return not MediaService().uses_api_upload
    except Exception:
        return False


@router.get("/readiness")
async def system_readiness():
    """Агрегированная проверка перед production (без секретов)."""
    payments = collect_payments_issues()
    media = collect_media_issues()
    production = collect_production_issues()
    infrastructure = collect_infrastructure_issues()
    all_issues = payments + media + production + infrastructure
    infra = infrastructure_status()
    return {
        "app_env": settings.APP_ENV,
        "ready": len(all_issues) == 0,
        "issues": all_issues,
        "payments": {
            "ready": len(payments) == 0,
            "issues": payments,
        },
        "media": {
            "s3_configured": _s3_fully_configured(),
            "upload_mode": media_upload_mode(),
            "ffmpeg_available": ffmpeg_available(),
            "issues": media,
        },
        "infrastructure": {
            "database": {"ok": bool((infra.get("database") or {}).get("ok"))},
            "redis": {
                "enabled": bool((infra.get("redis") or {}).get("enabled")),
                "ok": bool((infra.get("redis") or {}).get("ok")),
            },
            "firebase": {
                "enabled": bool((infra.get("firebase") or {}).get("enabled")),
                "push_ready": bool((infra.get("firebase") or {}).get("push_ready")),
            },
        },
        "production_issues": production,
    }
