"""Проверка готовности платёжной конфигурации при старте API."""
from __future__ import annotations

import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


def collect_payments_issues() -> list[str]:
    issues: list[str] = []
    if settings.TBANK_ENABLED:
        return _collect_tbank_issues()
    if settings.YOOKASSA_ENABLED:
        return _collect_yookassa_issues()
    issues.append(
        "TBANK_ENABLED и YOOKASSA_ENABLED выключены — оплата подписок недоступна"
    )
    return issues


def _collect_tbank_issues() -> list[str]:
    issues: list[str] = []
    if not settings.TBANK_TERMINAL_KEY:
        issues.append("TBANK_TERMINAL_KEY не задан")
    if not settings.TBANK_PASSWORD:
        issues.append("TBANK_PASSWORD не задан")

    if settings.APP_ENV == "production":
        if "localhost" in (settings.FRONTEND_URL or "").lower():
            issues.append("FRONTEND_URL указывает на localhost в production")
        if "127.0.0.1" in (settings.API_PUBLIC_BASE_URL or ""):
            issues.append(
                "API_PUBLIC_BASE_URL — localhost; webhook Т-Банка должен быть публичным HTTPS URL"
            )

    try:
        from app.services.tbank_service import get_tbank_service

        if settings.TBANK_TERMINAL_KEY and settings.TBANK_PASSWORD:
            tb = get_tbank_service()
            if not tb.enabled:
                issues.append(
                    "Т-Банк не инициализирован (проверьте TBANK_TERMINAL_KEY и TBANK_PASSWORD)"
                )
    except Exception as e:
        issues.append(f"T-Bank init error: {e}")

    return issues


def _collect_yookassa_issues() -> list[str]:
    issues: list[str] = []
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
    if settings.TBANK_ENABLED:
        webhook = (
            f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}/api/v1/payments/webhook/tbank"
        )
        recurring = (
            "СБП автопродление включено"
            if settings.TBANK_SBP_RECURRING_ENABLED
            else "СБП автопродление выключено"
        )
        if issues:
            for msg in issues:
                logger.warning("Payments: %s", msg)
        else:
            logger.info(
                "Payments: T-Bank ready (%s). Webhook URL (настройте в ЛК): %s",
                recurring,
                webhook,
            )
        return

    webhook = f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}/api/v1/payments/webhook/yookassa"
    if issues:
        for msg in issues:
            logger.warning("Payments: %s", msg)
    else:
        recurring = (
            "СБП автопродление включено"
            if settings.YOOKASSA_SBP_RECURRING_ENABLED
            else "СБП автопродление выключено"
        )
        logger.info(
            "Payments: YooKassa ready (%s). Webhook URL (настройте в ЛК): %s",
            recurring,
            webhook,
        )
