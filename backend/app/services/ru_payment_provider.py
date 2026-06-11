"""Выбор платёжного провайдера для RU/BY/KZ."""
from __future__ import annotations

from typing import Any, Protocol

from app.core.config import settings


class RuPaymentGateway(Protocol):
    enabled: bool

    def receipt_item_description(self, product: str, plan: str = "monthly") -> str: ...

    def create_payment(self, **kwargs: Any) -> dict: ...


def ru_checkout_provider_name() -> str:
    """Имя провайдера для CountryService / checkout."""
    if settings.TBANK_ENABLED:
        return "tbank"
    if settings.YOOKASSA_ENABLED:
        return "yookassa"
    return "none"


def get_active_ru_gateway():
    """Активный шлюз оплаты для России (Т-Банк приоритетнее ЮKassa)."""
    if settings.TBANK_ENABLED:
        from app.services.tbank_service import get_tbank_service

        return get_tbank_service()
    if settings.YOOKASSA_ENABLED:
        from app.services.yookassa_service import get_yookassa_service

        return get_yookassa_service()
    return None
