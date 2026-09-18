"""Русские названия позиций в чеках и истории оплат."""

from __future__ import annotations

from typing import Optional

PRODUCT_LABELS = {
    "ai": "HanWe · уровень 9",
    "creator": "HanWe · уровень 16",
    "pro": "HanWe · уровень 18",
    "flex": "HanWe",
    "stars": "Звёзды HanWe",
    "free": "Бесплатный",
}


def product_label(product: Optional[str], level: Optional[int] = None) -> str:
    if level is not None:
        return f"HanWe · уровень {int(level)}"
    if not product:
        return "HanWe"
    return PRODUCT_LABELS.get(str(product).lower(), "HanWe")


def receipt_item_description(
    product: str,
    plan: str = "monthly",
    level: Optional[int] = None,
) -> str:
    period = "1 мес." if plan == "monthly" else "1 год"
    return f"Подписка {product_label(product, level)} ({period})"
