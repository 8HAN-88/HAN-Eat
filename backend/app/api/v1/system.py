"""Системные эндпоинты: readiness для деплоя."""
from fastapi import APIRouter

from app.core.config import settings
from app.core.infrastructure_startup import (
    collect_infrastructure_issues,
    infrastructure_status,
)
from app.core.media_startup import collect_media_issues
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
    base = settings.API_PUBLIC_BASE_URL.rstrip("/")
    return {
        "app_env": settings.APP_ENV,
        "ready": len(all_issues) == 0,
        "issues": all_issues,
        "payments": {
            "webhook_url": f"{base}/api/v1/payments/webhook/yookassa",
            "issues": payments,
        },
        "media": {
            "s3_configured": _s3_fully_configured(),
            "cdn_url": settings.CDN_URL,
            "issues": media,
        },
        "infrastructure": infrastructure_status(),
        "production_issues": production,
    }
