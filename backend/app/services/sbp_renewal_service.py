"""
Автопродление подписок через СБП (Т-Банк или ЮKassa).
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.subscription import Subscription
from app.models.user import User
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)

_BATCH = 50
_RENEWAL_LEAD = timedelta(hours=24)


class SbpRenewalService:
    def __init__(self, db: Session):
        self.db = db
        self.sub_svc = SubscriptionService(db)

    def run(self) -> int:
        if settings.TBANK_ENABLED and settings.TBANK_SBP_RECURRING_ENABLED:
            return self._run_tbank()
        if settings.YOOKASSA_ENABLED and settings.YOOKASSA_SBP_RECURRING_ENABLED:
            return self._run_yookassa()
        return 0

    def reconcile_pending_renewals(self) -> int:
        if settings.TBANK_ENABLED:
            return self._reconcile_tbank()
        if settings.YOOKASSA_ENABLED:
            return self._reconcile_yookassa()
        return 0

    def _run_tbank(self) -> int:
        from app.services.tbank_service import get_tbank_service

        tbank = get_tbank_service()
        if not tbank.enabled or not tbank.sbp_recurring_enabled():
            return 0
        return self._run_for_provider("tbank", "tbank_rebill_id", tbank)

    def _run_yookassa(self) -> int:
        from app.services.yookassa_service import get_yookassa_service

        yk = get_yookassa_service()
        if not yk.enabled or not yk.sbp_recurring_enabled():
            return 0
        return self._run_for_provider(
            "yookassa", "yookassa_payment_method_id", yk
        )

    def _run_for_provider(self, provider: str, token_column: str, gateway) -> int:
        now = datetime.utcnow()
        window_end = now + _RENEWAL_LEAD
        initiated = 0
        offset = 0

        while True:
            rebill_col = getattr(User, token_column)
            rows = (
                self.db.query(Subscription, User)
                .join(User, User.id == Subscription.user_id)
                .filter(
                    Subscription.status == "active",
                    Subscription.auto_renew.is_(True),
                    User.subscription_auto_renew.is_(True),
                    rebill_col.isnot(None),
                    Subscription.payment_provider == provider,
                    Subscription.expires_at.isnot(None),
                    Subscription.expires_at <= window_end,
                    Subscription.expires_at > now - timedelta(days=2),
                    or_(
                        Subscription.pending_renewal_payment_id.is_(None),
                        Subscription.pending_renewal_payment_id == "",
                    ),
                )
                .order_by(Subscription.expires_at.asc())
                .offset(offset)
                .limit(_BATCH)
                .all()
            )
            if not rows:
                break
            for sub, user in rows:
                if self._initiate_renewal(sub, user, gateway, provider, token_column):
                    initiated += 1
            offset += len(rows)
            if len(rows) < _BATCH:
                break

        if initiated:
            logger.info("SBP renewal (%s): initiated %s autopayment(s)", provider, initiated)
        return initiated

    def _initiate_renewal(
        self, sub: Subscription, user: User, gateway, provider: str, token_column: str
    ) -> bool:
        rebill_id = getattr(user, token_column, None)
        if not rebill_id:
            return False

        product = getattr(sub, "product", None) or "pro"
        plan = sub.plan or "monthly"
        amount = float(self.sub_svc.price_for_product(product, plan))
        metadata = {"renewal": "1", "subscription_id": str(sub.id)}

        try:
            if provider == "tbank":
                result = gateway.create_autopayment(
                    user_id=user.id,
                    user_email=user.email,
                    amount=amount,
                    plan=plan,
                    product=product,
                    rebill_id=str(rebill_id),
                    description=gateway.receipt_item_description(product, plan),
                    metadata_extra=metadata,
                )
            else:
                result = gateway.create_autopayment(
                    user_id=user.id,
                    user_email=user.email,
                    amount=amount,
                    plan=plan,
                    product=product,
                    payment_method_id=str(rebill_id),
                    description=gateway.receipt_item_description(product, plan),
                    metadata_extra=metadata,
                )
        except Exception as e:
            logger.warning(
                "SBP renewal failed sub=%s user=%s: %s", sub.id, user.id, e
            )
            self.sub_svc.disable_auto_renew_after_failed_payment(sub)
            return False

        payment_id = result.get("payment_id")
        if not payment_id:
            return False

        self.sub_svc.mark_renewal_payment_pending(sub, payment_id)

        if result.get("paid"):
            info = gateway.get_payment_state(payment_id)
            if info and info.get("paid"):
                self._complete_renewal(sub, info, provider)

        return True

    def _complete_renewal(
        self, sub: Subscription, payment_info: dict, provider: str
    ) -> None:
        from app.services.payment_success_handler import process_payment_succeeded

        payment_id = payment_info.get("id") or payment_info.get("payment_id")
        if not payment_id:
            return
        process_payment_succeeded(
            self.db,
            payment_provider=provider,
            payment_id=str(payment_id),
            payment_info=payment_info,
        )

    def _reconcile_tbank(self) -> int:
        from app.services.tbank_service import get_tbank_service

        return self._reconcile(get_tbank_service(), "tbank")

    def _reconcile_yookassa(self) -> int:
        from app.services.yookassa_service import get_yookassa_service

        return self._reconcile(get_yookassa_service(), "yookassa")

    def _reconcile(self, gateway, provider: str) -> int:
        if not gateway.enabled:
            return 0
        now = datetime.utcnow()
        stale_before = now - timedelta(hours=6)
        updated = 0
        subs = (
            self.db.query(Subscription)
            .filter(
                Subscription.payment_provider == provider,
                Subscription.pending_renewal_payment_id.isnot(None),
                Subscription.pending_renewal_payment_id != "",
            )
            .limit(_BATCH)
            .all()
        )
        for sub in subs:
            pid = sub.pending_renewal_payment_id
            info = gateway.get_payment_state(pid)
            if not info:
                continue
            if info.get("paid"):
                self._complete_renewal(sub, info, provider)
                updated += 1
            elif info.get("status") in ("CANCELED", "REJECTED", "REVERSED") and (
                sub.expires_at and sub.expires_at < stale_before
            ):
                self.sub_svc.disable_auto_renew_after_failed_payment(sub)
                updated += 1
        return updated
