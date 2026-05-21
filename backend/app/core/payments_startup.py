"""Проверка готовности платёжной конфигурации при старте API."""
from __future__ import annotations

import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


def collect_payments_issues() -> list[str]:
    issues: list[str] = []
    if not settings.YOOKASSA_ENABLED:
        issues.append("YOOKASSA_ENABLED=false — оплата подписок недоступна")
        return issues

    if not settings.YOOKASSA_SHOP_ID:
        issues.append("YOOKASSA_SHOP_ID не задан")
    if not settings.YOOKASSA_SECRET_KEY:
        issues.append("YOOKASSA_SECRET_KEY не задан")

    if settings.APP_ENV == "production":
        if "localhost" in (settings.FRONTEND_URL or "").lower():
            issues.append("FRONTEND_URL указывает на localhost в production")
        if "127.0.0.1" in (settings.API_PUBLIC_BASE_URL or ""):
            issues.append(
                "API_PUBLIC_BASE_URL — localhost; webhook ЮKassa должен быть публичным HTTPS URL"
            )

    try:
        from app.services.yookassa_service import get_yookassa_service

        if settings.YOOKASSA_SHOP_ID and settings.YOOKASSA_SECRET_KEY:
            yk = get_yookassa_service()
            if not yk.enabled:
                issues.append("ЮKassa SDK не инициализирован (проверьте ключи и пакет yookassa)")
    except Exception as e:
        issues.append(f"ЮKassa init error: {e}")

    return issues


def log_payments_readiness() -> None:
    issues = collect_payments_issues()
    webhook = f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}/api/v1/payments/webhook/yookassa"
    if issues:
        for msg in issues:
            logger.warning("Payments: %s", msg)
    else:
        logger.info(
            "Payments: YooKassa ready. Webhook URL (настройте в ЛК): %s",
            webhook,
        )
