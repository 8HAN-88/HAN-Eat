"""Общая обработка успешной оплаты подписки (Т-Банк / ЮKassa)."""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.subscription import Subscription
from app.services.analytics_service import AnalyticsService
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)


def process_payment_succeeded(
    db: Session,
    *,
    payment_provider: str,
    payment_id: str,
    payment_info: Dict[str, Any],
) -> None:
    """Активировать или продлить подписку после подтверждённого платежа."""
    subscription_service = SubscriptionService(db)
    existing = subscription_service.get_subscription_by_provider_payment_id(
        payment_id, payment_provider
    )
    if existing:
        subscription_service.refresh_receipt_url(existing)
        logger.info(
            "%s payment %s already linked to subscription %s",
            payment_provider,
            payment_id,
            existing.id,
        )
        return

    if not payment_info or not payment_info.get("paid"):
        logger.warning("%s payment %s not paid", payment_provider, payment_id)
        return

    metadata = payment_info.get("metadata") or {}
    try:
        user_id = int(metadata.get("user_id") or payment_info.get("user_id") or 0)
    except (TypeError, ValueError):
        user_id = 0
    plan = metadata.get("plan") or "monthly"
    product = metadata.get("product") or "pro"
    is_renewal = metadata.get("renewal") == "1"

    if not user_id:
        logger.error(
            "%s payment %s missing user_id in metadata", payment_provider, payment_id
        )
        return

    if product == "stars":
        try:
            stars = int(metadata.get("stars") or 0)
        except (TypeError, ValueError):
            stars = 0
        if stars <= 0:
            logger.error("%s payment %s missing stars metadata", payment_provider, payment_id)
            return
        from app.services.paid_features_service import PaidFeaturesService

        PaidFeaturesService(db).add_stars(
            user_id,
            stars,
            tx_type="purchase",
            provider=payment_provider,
            provider_payment_id=payment_id,
            idempotency_key=f"{payment_provider}:stars:{payment_id}",
            meta={
                "package_id": metadata.get("package_id"),
                "amount_rub": payment_info.get("amount"),
            },
        )
        AnalyticsService(db).log_event(
            event_type="stars_purchase_success",
            entity_type="user",
            entity_id=user_id,
            user_id=user_id,
            metadata={
                "stars": stars,
                "package_id": metadata.get("package_id"),
                "provider": payment_provider,
                "amount": payment_info.get("amount"),
            },
        )
        logger.info(
            "Credited %s stars to user %s via %s payment %s",
            stars,
            user_id,
            payment_provider,
            payment_id,
        )
        return

    if product == "flex":
        from app.services.flex_subscription_service import (
            FlexSubscriptionService,
            price_for_level,
        )

        try:
            flex_level = int(metadata.get("flex_level") or 1)
        except (TypeError, ValueError):
            flex_level = 1
        amount = float(payment_info.get("amount") or 0)
        if amount <= 0:
            amount = float(price_for_level(flex_level))

        rebill_id = payment_info.get("rebill_id") or payment_info.get("payment_method_id")
        if rebill_id and _should_save_rebill(payment_provider):
            p = (payment_provider or "").lower()
            if p == "tbank":
                subscription_service.save_tbank_rebill_id(user_id, str(rebill_id))
            elif p == "yookassa" and (
                payment_info.get("payment_method_saved") is not False
            ):
                subscription_service.save_yookassa_payment_method(user_id, str(rebill_id))

        auto_renew = _should_save_rebill(payment_provider) and bool(rebill_id)
        if is_renewal:
            sub = _find_renewal_subscription(
                db, user_id, metadata, payment_id, subscription_service
            )
            if sub:
                subscription_service.apply_renewal_payment(
                    sub,
                    payment_id,
                    amount,
                    receipt_url=payment_info.get("receipt_url"),
                    rebill_id=str(rebill_id) if rebill_id else None,
                    payment_provider=payment_provider,
                )
                AnalyticsService(db).log_event(
                    event_type="flex_subscription_renewal_success",
                    entity_type="subscription",
                    entity_id=sub.id,
                    user_id=user_id,
                    metadata={
                        "product": "flex",
                        "flex_level": flex_level,
                        "amount": amount,
                        "provider": payment_provider,
                    },
                )
                logger.info(
                    "Flex subscription %s renewed for user %s at level %s",
                    sub.id,
                    user_id,
                    flex_level,
                )
                return
            logger.warning(
                "%s flex renewal %s: subscription not found for user %s",
                payment_provider,
                payment_id,
                user_id,
            )

        keep_raw = str(metadata.get("keep_expires") or "").strip().lower()
        keep_expires = keep_raw in ("1", "true", "yes") if keep_raw else None
        FlexSubscriptionService(db).record_payment_subscription(
            user_id,
            level=flex_level,
            amount=amount,
            payment_provider=payment_provider,
            payment_id=payment_id,
            receipt_url=payment_info.get("receipt_url"),
            auto_renew=auto_renew,
            keep_expires=keep_expires,
        )
        AnalyticsService(db).log_event(
            event_type="flex_subscription_payment_success",
            entity_type="user",
            entity_id=user_id,
            user_id=user_id,
            metadata={
                "product": "flex",
                "flex_level": flex_level,
                "amount": amount,
                "provider": payment_provider,
                "is_upgrade": metadata.get("is_upgrade") == "1",
            },
        )
        logger.info(
            "Activated flex level %s for user %s via %s payment %s",
            flex_level,
            user_id,
            payment_provider,
            payment_id,
        )
        return

    amount = float(payment_info.get("amount") or 0)
    if amount <= 0:
        amount = float(subscription_service.price_for_product(product, plan, user_id=user_id))

    rebill_id = payment_info.get("rebill_id") or payment_info.get("payment_method_id")
    if rebill_id and _should_save_rebill(payment_provider):
        p = (payment_provider or "").lower()
        if p == "tbank":
            subscription_service.save_tbank_rebill_id(user_id, str(rebill_id))
        elif p == "yookassa" and (
            payment_info.get("payment_method_saved") is not False
        ):
            subscription_service.save_yookassa_payment_method(user_id, str(rebill_id))

    if is_renewal:
        sub = _find_renewal_subscription(
            db, user_id, metadata, payment_id, subscription_service
        )
        if sub:
            subscription_service.apply_renewal_payment(
                sub,
                payment_id,
                amount,
                receipt_url=payment_info.get("receipt_url"),
                rebill_id=str(rebill_id) if rebill_id else None,
                payment_provider=payment_provider,
            )
            AnalyticsService(db).log_event(
                event_type="subscription_renewal_success",
                entity_type="subscription",
                entity_id=sub.id,
                user_id=user_id,
                metadata={
                    "product": product,
                    "plan": plan,
                    "amount": amount,
                    "provider": "sbp",
                    "payment_backend": payment_provider,
                },
            )
            logger.info(
                "Subscription %s renewed for user %s via %s",
                sub.id,
                user_id,
                payment_provider,
            )
            return
        logger.warning(
            "%s renewal payment %s: subscription not found for user %s",
            payment_provider,
            payment_id,
            user_id,
        )

    subscription = subscription_service.create_subscription(
        user_id=user_id,
        plan=plan,
        product=product,
        payment_provider=payment_provider,
        payment_provider_subscription_id=payment_id,
        amount=amount,
        currency=payment_info.get("currency") or "RUB",
        platform="sbp",
        receipt_url=payment_info.get("receipt_url"),
    )

    AnalyticsService(db).log_event(
        event_type="subscription_payment_success",
        entity_type="subscription",
        entity_id=subscription.id,
        user_id=user_id,
        metadata={
            "product": product,
            "plan": plan,
            "amount": amount,
            "provider": "sbp",
            "payment_backend": payment_provider,
            "is_upgrade": metadata.get("is_upgrade") == "1",
            "recurring_enabled": bool(rebill_id),
        },
    )
    logger.info(
        "Subscription created for user %s via %s: %s",
        user_id,
        payment_provider,
        subscription.id,
    )


def _should_save_rebill(payment_provider: str) -> bool:
    p = (payment_provider or "").lower()
    if p == "tbank":
        return bool(settings.TBANK_SBP_RECURRING_ENABLED)
    if p == "yookassa":
        return bool(settings.YOOKASSA_SBP_RECURRING_ENABLED)
    return False


def _find_renewal_subscription(
    db: Session,
    user_id: int,
    metadata: Dict[str, Any],
    payment_id: str,
    subscription_service: SubscriptionService,
) -> Optional[Subscription]:
    sub_id_raw = metadata.get("subscription_id")
    if sub_id_raw:
        try:
            sub = (
                db.query(Subscription)
                .filter(
                    Subscription.id == int(sub_id_raw),
                    Subscription.user_id == user_id,
                )
                .first()
            )
            if sub:
                return sub
        except (TypeError, ValueError):
            pass
    return (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user_id,
            Subscription.pending_renewal_payment_id == payment_id,
        )
        .first()
    )
