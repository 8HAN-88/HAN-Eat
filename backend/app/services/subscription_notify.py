"""Push/in-app уведомления по подпискам и возвратам."""
from __future__ import annotations

import logging
from typing import Optional

from sqlalchemy.orm import Session

from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)

_PRODUCT_NAMES = {
    "ai": "H.A.N. AI",
    "creator": "H.A.N. Creator",
    "pro": "H.A.N. Pro",
}


def _product_label(product: Optional[str]) -> str:
    if not product:
        return "подписка"
    return _PRODUCT_NAMES.get(str(product).lower(), product)


def notify_refund_requested(
    db: Session,
    *,
    user_id: int,
    subscription_id: int,
    amount: float,
    product: str,
) -> None:
    try:
        NotificationService(db).create_notification(
            user_id=user_id,
            type="subscription_refund_requested",
            title="Запрос на возврат принят",
            body=(
                f"Мы получили запрос на возврат {amount:.0f} ₽ "
                f"за {_product_label(product)}. Ответим в ближайшее время."
            ),
            entity_type="subscription",
            entity_id=subscription_id,
            data={"route": "subscription", "subscription_id": subscription_id},
        )
    except Exception:
        logger.exception("notify_refund_requested failed user_id=%s", user_id)


def notify_refund_approved(
    db: Session,
    *,
    user_id: int,
    subscription_id: int,
    amount: float,
    product: str,
) -> None:
    try:
        NotificationService(db).create_notification(
            user_id=user_id,
            type="subscription_refund_approved",
            title="Возврат выполнен",
            body=(
                f"На ваш счёт возвращено {amount:.0f} ₽ "
                f"за {_product_label(product)}. Срок зачисления зависит от банка."
            ),
            entity_type="subscription",
            entity_id=subscription_id,
            data={"route": "subscription", "subscription_id": subscription_id},
        )
    except Exception:
        logger.exception("notify_refund_approved failed user_id=%s", user_id)


def notify_refund_rejected(
    db: Session,
    *,
    user_id: int,
    subscription_id: int,
    product: str,
    comment: Optional[str] = None,
) -> None:
    body = (
        f"Запрос на возврат за {_product_label(product)} отклонён. "
        "Подробности — в поддержке."
    )
    if comment and comment.strip():
        body = f"{body} {comment.strip()}"
    try:
        NotificationService(db).create_notification(
            user_id=user_id,
            type="subscription_refund_rejected",
            title="Возврат не выполнен",
            body=body[:500],
            entity_type="subscription",
            entity_id=subscription_id,
            data={"route": "subscription", "subscription_id": subscription_id},
        )
    except Exception:
        logger.exception("notify_refund_rejected failed user_id=%s", user_id)
