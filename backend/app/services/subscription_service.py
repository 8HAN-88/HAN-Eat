"""
Сервис подписок: тарифы free | ai | creator | pro.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Optional, Tuple

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.entitlements import (
    SubscriptionTier,
    normalize_tier,
    subscription_status_payload,
)
from app.models.subscription import Subscription
from app.models.user import User

TIER_PRICES_RUB = {
    "ai": lambda: settings.AI_MONTHLY_PRICE_RUB,
    "creator": lambda: settings.CREATOR_MONTHLY_PRICE_RUB,
    "pro": lambda: settings.PRO_MONTHLY_PRICE_RUB,
}

TIER_ORDER = ("free", "ai", "creator", "pro")


def _payment_auto_renew_enabled(payment_provider: str) -> bool:
    """Автопродление: Stripe — да; Т-Банк/ЮKassa — по флагу рекуррента в настройках."""
    p = (payment_provider or "").strip().lower()
    if p == "stripe":
        return True
    if p == "tbank":
        return bool(settings.TBANK_SBP_RECURRING_ENABLED)
    if p == "yookassa":
        return bool(settings.YOOKASSA_SBP_RECURRING_ENABLED)
    return False


def _is_trial_status(status: Optional[str]) -> bool:
    return (status or "").strip().lower() == "trial"


def upgrade_options_for_tier(tier: SubscriptionTier, is_active: bool) -> list:
    """Классические тарифы сняты — апгрейд только через уровни flex."""
    return []


def _tier_display(product: str) -> str:
    return {
        "ai": "HanWe AI",
        "creator": "HanWe Creator",
        "pro": "HanWe Pro",
    }.get(product, product)


def build_upgrade_options(
    db: Session,
    user_id: int,
    tier: SubscriptionTier,
    is_active: bool,
) -> list:
    """Опции апгрейда с оценкой суммы к оплате (прорация остатка текущего тарифа)."""
    raw = upgrade_options_for_tier(tier, is_active)
    svc = SubscriptionService(db)
    enriched = []
    for opt in raw:
        est = svc.estimate_upgrade_charge(user_id, opt["product"])
        enriched.append({**opt, **est})
    return enriched


class SubscriptionService:
    def __init__(self, db: Session):
        self.db = db

    def get_user_subscription(self, user_id: int) -> Optional[Subscription]:
        now = datetime.utcnow()
        return (
            self.db.query(Subscription)
            .filter(
                Subscription.user_id == user_id,
                Subscription.expires_at > now,
                or_(
                    Subscription.status == "active",
                    Subscription.status == "cancelled",
                    Subscription.status == "trial",
                ),
            )
            .order_by(Subscription.expires_at.desc())
            .first()
        )

    def effective_tier(self, user_id: int) -> Tuple[SubscriptionTier, bool]:
        """(tier, is_active_paid) — включая grace period после expires_at."""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return "free", False

        grace = timedelta(days=int(settings.SUBSCRIPTION_GRACE_PERIOD_DAYS or 3))
        now = datetime.utcnow()

        sub = self.get_user_subscription(user_id)
        if sub and sub.expires_at:
            product = normalize_tier(getattr(sub, "product", None) or user.subscription_type)
            if sub.expires_at > now:
                return product, True
            if not _is_trial_status(sub.status) and sub.expires_at + grace > now:
                return product, True

        tier = normalize_tier(user.subscription_type)
        if tier == "free":
            return "free", False
        if user.subscription_expires_at:
            if user.subscription_expires_at > now:
                return tier, True
            if (
                not _is_trial_status(user.subscription_status)
                and user.subscription_expires_at + grace > now
            ):
                return tier, True
        return "free", False

    def in_grace_period(self, user_id: int) -> bool:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return False
        grace = timedelta(days=int(settings.SUBSCRIPTION_GRACE_PERIOD_DAYS or 3))
        now = datetime.utcnow()
        sub = self.get_user_subscription(user_id)
        expires = sub.expires_at if sub else user.subscription_expires_at
        if not expires or normalize_tier(user.subscription_type) == "free":
            return False
        if _is_trial_status(sub.status if sub else user.subscription_status):
            return False
        return expires < now <= expires + grace

    def is_user_plus(self, user_id: int) -> bool:
        """Совместимость: Plus = доступ к AI."""
        return self.has_ai_access(user_id)

    def has_ai_access(self, user_id: int) -> bool:
        self._ensure_flex(user_id)
        return self._flex_has_any(user_id, "ai")

    def has_creator_access(self, user_id: int) -> bool:
        self._ensure_flex(user_id)
        return self._flex_has_any(user_id, "creator")

    def has_priority_support(self, user_id: int) -> bool:
        self._ensure_flex(user_id)
        return self._flex_has_any(user_id, "pro")

    def _ensure_flex(self, user_id: int) -> None:
        try:
            from app.services.flex_subscription_service import FlexSubscriptionService

            FlexSubscriptionService(self.db).migrate_legacy_if_needed(user_id)
        except Exception:
            return

    def _flex_has_any(self, user_id: int, kind: str) -> bool:
        try:
            from app.services.flex_subscription_service import (
                AI_FEATURE_SLUGS,
                CREATOR_FEATURE_SLUGS,
                PRO_FEATURE_SLUGS,
                FlexSubscriptionService,
            )

            slugs = FlexSubscriptionService(self.db).unlocked_slugs(user_id)
        except Exception:
            return False
        if kind == "ai":
            return bool(slugs & AI_FEATURE_SLUGS)
        if kind == "creator":
            return bool(slugs & CREATOR_FEATURE_SLUGS)
        if kind == "pro":
            return bool(slugs & PRO_FEATURE_SLUGS)
        return False

    def get_status_dict(self, user_id: int) -> Dict[str, Any]:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return subscription_status_payload(
                tier="free",
                status="active",
                expires_at=None,
                platform=None,
                auto_renew=False,
                is_active=False,
            )
        sub = self.get_user_subscription(user_id)
        tier, is_active = self.effective_tier(user_id)
        status = (user.subscription_status or "active").lower()
        if not is_active:
            status = "expired"
        elif sub and sub.status == "trial":
            status = "trial"
        expires = sub.expires_at if sub else user.subscription_expires_at
        platform = user.subscription_platform or (sub.payment_provider if sub else None)
        auto_renew = bool(
            user.subscription_auto_renew if user.subscription_auto_renew is not None else (sub.auto_renew if sub else False)
        )
        payload = subscription_status_payload(
            tier=tier,
            status=status,
            expires_at=expires,
            platform=platform,
            auto_renew=auto_renew,
            is_active=is_active,
        )
        payload["in_grace_period"] = self.in_grace_period(user_id)
        payload["upgrade_options"] = []
        payload["trial_eligible"] = {"flex": self.trial_eligible(user_id, "flex")}
        if sub:
            payload["subscription"] = {
                "id": sub.id,
                "plan": sub.plan,
                "product": getattr(sub, "product", "pro"),
                "status": sub.status,
                "payment_provider": sub.payment_provider,
                "amount": float(sub.amount),
                "currency": sub.currency,
                "started_at": sub.started_at.isoformat() if sub.started_at else None,
                "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
                "auto_renew": sub.auto_renew,
            }
        else:
            payload["subscription"] = None
        try:
            from app.services.flex_subscription_service import (
                AI_FEATURE_SLUGS,
                CREATOR_FEATURE_SLUGS,
                PRO_FEATURE_SLUGS,
                FlexSubscriptionService,
            )

            flex = FlexSubscriptionService(self.db)
            flex.migrate_legacy_if_needed(user_id)
            if flex.is_flex_active(user_id):
                slugs = flex.unlocked_slugs(user_id)
                ents = {k: False for k in (payload.get("entitlements") or {})}
                for slug in slugs:
                    ents[slug] = True
                ents["ad_free"] = "ad_free" in slugs
                ents["premium_badge"] = bool(slugs)
                ents["is_plus"] = bool(slugs & AI_FEATURE_SLUGS)
                ents["pro"] = bool(slugs & PRO_FEATURE_SLUGS)
                payload["entitlements"] = ents
                payload["has_ai"] = bool(slugs & AI_FEATURE_SLUGS)
                payload["has_creator"] = bool(slugs & CREATOR_FEATURE_SLUGS)
                payload["is_plus"] = payload["has_ai"]
                payload["is_active"] = True
                payload["subscription_type"] = "flex"
                me = flex.me_payload(user_id)
                payload["flex"] = {
                    "active": True,
                    "level": me.get("current_level"),
                    "price_rub": me.get("price_rub"),
                    "expires_at": me.get("expires_at"),
                }
                expires = me.get("expires_at")
                if expires:
                    payload["subscription_expire_at"] = expires
        except Exception:
            pass
        return payload

    def create_subscription(
        self,
        user_id: int,
        plan: str,
        payment_provider: str,
        payment_provider_subscription_id: str,
        amount: float,
        currency: str = "RUB",
        product: str = "pro",
        *,
        stripe_subscription_id: Optional[str] = None,
        expires_at: Optional[datetime] = None,
        is_trial: bool = False,
        platform: Optional[str] = None,
        receipt_url: Optional[str] = None,
    ) -> Subscription:
        p = (product or "flex").strip().lower()
        from app.services.flex_subscription_service import LEGACY_TIER_LEVELS

        flex_level = LEGACY_TIER_LEVELS.get(p)
        if p == "flex":
            flex_level = flex_level or 6
        elif p not in ("ai", "creator", "pro", "flex"):
            p = "flex"
            flex_level = 6
        product = "flex"

        for sub in self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(("active", "trial")),
        ):
            sub.status = "cancelled"
            sub.cancelled_at = datetime.utcnow()

        if expires_at is None:
            expires_at = datetime.utcnow() + timedelta(days=30 if plan == "monthly" else 365)

        provider_sub_id = stripe_subscription_id or payment_provider_subscription_id
        sub_status = "trial" if is_trial else "active"
        auto_renew = _payment_auto_renew_enabled(payment_provider)

        subscription = Subscription(
            user_id=user_id,
            plan=plan,
            product=product,
            status=sub_status,
            payment_provider=payment_provider,
            payment_provider_subscription_id=provider_sub_id,
            amount=amount,
            currency=currency,
            expires_at=expires_at,
            auto_renew=auto_renew,
            receipt_url=receipt_url,
            refund_status="none",
        )

        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            user.subscription_type = "flex"
            user.subscription_status = sub_status
            user.subscription_expires_at = expires_at
            user.subscription_platform = platform or payment_provider
            user.subscription_auto_renew = auto_renew

        self.db.add(subscription)
        self.db.flush()
        try:
            from app.services.flex_subscription_service import FlexSubscriptionService

            flex_row = FlexSubscriptionService(self.db).activate(
                user_id,
                int(flex_level or 6),
                payment_subscription_id=subscription.id,
                months=1,
                auto_renew=auto_renew,
            )
            flex_row.expires_at = expires_at
        except Exception:
            pass
        self.db.commit()
        self.db.refresh(subscription)

        return subscription

    def cancel_subscription(
        self,
        user_id: int,
        subscription_id: Optional[int] = None,
    ) -> bool:
        if subscription_id:
            subscription = (
                self.db.query(Subscription)
                .filter(
                    Subscription.id == subscription_id,
                    Subscription.user_id == user_id,
                )
                .first()
            )
        else:
            subscription = self.get_user_subscription(user_id)

        if not subscription:
            return False

        subscription.status = "cancelled"
        subscription.cancelled_at = datetime.utcnow()
        subscription.auto_renew = False
        subscription.pending_renewal_payment_id = None
        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            user.subscription_auto_renew = False
            user.subscription_status = "canceled"
            user.yookassa_payment_method_id = None
            user.tbank_rebill_id = None
        self.db.commit()
        return True

    def save_tbank_rebill_id(self, user_id: int, rebill_id: Optional[str]) -> None:
        if not rebill_id:
            return
        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            user.tbank_rebill_id = str(rebill_id)
            self.db.flush()

    def save_yookassa_payment_method(
        self, user_id: int, payment_method_id: Optional[str]
    ) -> None:
        if not payment_method_id:
            return
        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            user.yookassa_payment_method_id = str(payment_method_id)
            self.db.flush()

    def apply_renewal_payment(
        self,
        subscription: Subscription,
        payment_id: str,
        amount: float,
        *,
        receipt_url: Optional[str] = None,
        payment_method_id: Optional[str] = None,
        rebill_id: Optional[str] = None,
        payment_provider: Optional[str] = None,
    ) -> Subscription:
        """Продление существующей подписки после успешного автоплатежа СБП."""
        provider = payment_provider or subscription.payment_provider or "tbank"
        now = datetime.utcnow()
        base = subscription.expires_at if subscription.expires_at and subscription.expires_at > now else now
        if subscription.plan == "yearly":
            subscription.expires_at = base + timedelta(days=365)
        else:
            subscription.expires_at = base + timedelta(days=30)

        subscription.status = "active"
        subscription.auto_renew = _payment_auto_renew_enabled(provider)
        subscription.amount = amount
        subscription.payment_provider_subscription_id = payment_id
        subscription.pending_renewal_payment_id = None
        if receipt_url:
            subscription.receipt_url = receipt_url

        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            product = normalize_tier(getattr(subscription, "product", "pro"))
            user.subscription_type = product
            user.subscription_status = "active"
            user.subscription_expires_at = subscription.expires_at
            user.subscription_auto_renew = subscription.auto_renew
            token = rebill_id or payment_method_id
            if token and _payment_auto_renew_enabled(provider):
                if provider == "tbank":
                    user.tbank_rebill_id = str(token)
                elif provider == "yookassa":
                    user.yookassa_payment_method_id = str(token)

        self.db.commit()
        self.db.refresh(subscription)
        return subscription

    def mark_renewal_payment_pending(
        self, subscription: Subscription, payment_id: str
    ) -> None:
        subscription.pending_renewal_payment_id = payment_id
        self.db.flush()

    def clear_renewal_payment_pending(self, subscription: Subscription) -> None:
        subscription.pending_renewal_payment_id = None
        self.db.flush()

    def disable_auto_renew_after_failed_payment(
        self, subscription: Subscription, *, notify: bool = True
    ) -> None:
        subscription.auto_renew = False
        subscription.pending_renewal_payment_id = None
        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_auto_renew = False
            user.yookassa_payment_method_id = None
            user.tbank_rebill_id = None
        self.db.flush()
        if notify:
            try:
                from app.services.notification_service import NotificationService

                NotificationService(self.db).create_notification(
                    user_id=subscription.user_id,
                    type="subscription_renewal_failed",
                    title="Не удалось продлить подписку",
                    body=(
                        "Автоплатёж по СБП (Т-Банк) не прошёл. Продлите подписку вручную "
                        "в разделе «Подписка»."
                    ),
                    entity_type="subscription",
                    entity_id=subscription.id,
                    data={"route": "subscription"},
                )
            except Exception:
                pass

    def renew_subscription(self, subscription_id: int) -> bool:
        subscription = (
            self.db.query(Subscription).filter(Subscription.id == subscription_id).first()
        )
        if not subscription or subscription.status not in ("active", "trial"):
            return False
        if subscription.plan == "monthly":
            subscription.expires_at += timedelta(days=30)
        elif subscription.plan == "yearly":
            subscription.expires_at += timedelta(days=365)
        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_expires_at = subscription.expires_at
        self.db.commit()
        return True

    def get_subscription_by_provider_payment_id(
        self, payment_id: str, provider: str = "yookassa"
    ) -> Optional[Subscription]:
        if not payment_id:
            return None
        return (
            self.db.query(Subscription)
            .filter(
                Subscription.payment_provider == provider,
                Subscription.payment_provider_subscription_id == payment_id,
            )
            .first()
        )

    def revoke_access_after_refund(self, subscription: Subscription) -> None:
        """Снять доступ по оплаченному тарифу после возврата."""
        subscription.status = "cancelled"
        subscription.cancelled_at = datetime.utcnow()
        subscription.auto_renew = False

        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if not user:
            return

        tier, active = self.effective_tier(subscription.user_id)
        product = getattr(subscription, "product", "pro") or "pro"
        if active and tier == product:
            user.subscription_type = "free"
            user.subscription_status = "expired"
            user.subscription_expires_at = datetime.utcnow()
            user.subscription_auto_renew = False
            user.yookassa_payment_method_id = None
            user.tbank_rebill_id = None

    def apply_tbank_refund(
        self,
        subscription: Subscription,
        *,
        amount: Optional[float] = None,
        reason: str = "Возврат по запросу пользователя",  # noqa: ARG002
    ) -> Dict[str, Any]:
        """Провести возврат (Cancel) в Т-Банке и обновить подписку."""
        if getattr(subscription, "refund_status", None) == "refunded":
            raise ValueError("Subscription already refunded")

        pid = subscription.payment_provider_subscription_id
        if not pid or str(pid).startswith("trial-"):
            raise ValueError("No T-Bank payment linked to subscription")
        if subscription.payment_provider != "tbank":
            raise ValueError("Refunds only supported for T-Bank payments")

        refund_amount = float(amount) if amount is not None else float(subscription.amount)
        if refund_amount <= 0:
            raise ValueError("Refund amount must be positive")
        if refund_amount > float(subscription.amount) + 0.01:
            raise ValueError("Refund amount exceeds payment amount")

        from app.services.tbank_service import get_tbank_service

        tb = get_tbank_service()
        if not tb.enabled:
            raise ValueError("T-Bank is not enabled")

        amount_kop = int(round(refund_amount * 100))
        result = tb.cancel_payment(str(pid), amount_kopecks=amount_kop)

        subscription.refund_status = "refunded"
        subscription.refunded_at = datetime.utcnow()
        self.revoke_access_after_refund(subscription)

        return {
            "refund_id": result.get("PaymentId") or pid,
            "refund_status": result.get("Status"),
            "amount": refund_amount,
            "currency": subscription.currency or "RUB",
        }

    def apply_yookassa_refund(
        self,
        subscription: Subscription,
        *,
        amount: Optional[float] = None,
        reason: str = "Возврат по запросу пользователя",
    ) -> Dict[str, Any]:
        """Провести возврат в ЮKassa и обновить подписку."""
        if getattr(subscription, "refund_status", None) == "refunded":
            raise ValueError("Subscription already refunded")

        pid = subscription.payment_provider_subscription_id
        if not pid or str(pid).startswith("trial-"):
            raise ValueError("No YooKassa payment linked to subscription")
        if subscription.payment_provider != "yookassa":
            raise ValueError("Refunds only supported for YooKassa payments")

        refund_amount = float(amount) if amount is not None else float(subscription.amount)
        if refund_amount <= 0:
            raise ValueError("Refund amount must be positive")
        if refund_amount > float(subscription.amount) + 0.01:
            raise ValueError("Refund amount exceeds payment amount")

        from app.services.yookassa_service import get_yookassa_service

        yk = get_yookassa_service()
        if not yk.enabled:
            raise ValueError("YooKassa is not enabled")

        result = yk.create_refund(
            payment_id=str(pid),
            amount=refund_amount,
            currency=subscription.currency or "RUB",
            reason=reason,
        )

        subscription.refund_status = "refunded"
        subscription.refunded_at = datetime.utcnow()
        self.revoke_access_after_refund(subscription)

        return {
            "refund_id": result.get("refund_id"),
            "refund_status": result.get("status"),
            "amount": refund_amount,
            "currency": subscription.currency or "RUB",
        }

    def refresh_receipt_url(self, subscription: Subscription) -> Optional[str]:
        """Подтянуть URL чека из ЮKassa по payment_id."""
        pid = subscription.payment_provider_subscription_id
        if not pid or subscription.payment_provider != "yookassa":
            return subscription.receipt_url
        from app.services.yookassa_service import get_yookassa_service

        yk = get_yookassa_service()
        if not yk.enabled:
            return subscription.receipt_url
        info = yk.get_payment_status(pid)
        if info and info.get("receipt_url"):
            subscription.receipt_url = info["receipt_url"]
            self.db.commit()
        return subscription.receipt_url

    def sync_subscription_period_by_provider_id(
        self,
        payment_provider_subscription_id: str,
        period_end_ts: int,
        stripe_status: Optional[str] = None,
    ) -> bool:
        subscription = (
            self.db.query(Subscription)
            .filter(
                Subscription.payment_provider_subscription_id
                == payment_provider_subscription_id
            )
            .first()
        )
        if not subscription:
            return False

        expires_at = datetime.utcfromtimestamp(int(period_end_ts))
        subscription.expires_at = expires_at

        if stripe_status is not None:
            if stripe_status in ("active", "trialing"):
                subscription.status = "trial" if stripe_status == "trialing" else "active"
            elif stripe_status == "canceled":
                subscription.status = "cancelled"
                subscription.auto_renew = False

        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_expires_at = expires_at
            now = datetime.utcnow()
            product = normalize_tier(getattr(subscription, "product", "pro"))
            if expires_at > now and subscription.status in ("active", "cancelled", "trial"):
                user.subscription_type = product
                user.subscription_status = (
                    "trial" if subscription.status == "trial" else "active"
                )
            else:
                user.subscription_type = "free"
                user.subscription_status = "expired"
                user.subscription_expires_at = None

        self.db.commit()
        return True

    def expire_subscription(self, subscription_id: int) -> bool:
        subscription = (
            self.db.query(Subscription).filter(Subscription.id == subscription_id).first()
        )
        if not subscription:
            return False
        subscription.status = "expired"
        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_type = "free"
            user.subscription_status = "expired"
            user.subscription_expires_at = None
            user.subscription_auto_renew = False
        self.db.commit()
        return True

    def trial_eligible(self, user_id: int, product: str) -> bool:
        """Один пробный период гибкой подписки, если ещё не было оплат."""
        p = (product or "flex").strip().lower()
        if p not in ("flex", "ai", "pro"):
            return False
        had_any = (
            self.db.query(Subscription.id)
            .filter(Subscription.user_id == user_id)
            .first()
        )
        return had_any is None

    def start_trial(self, user_id: int, product: str = "flex") -> Subscription:
        if not self.trial_eligible(user_id, "flex"):
            raise ValueError("Пробный период недоступен")
        days = int(settings.SUBSCRIPTION_TRIAL_DAYS or 7)
        expires_at = datetime.utcnow() + timedelta(days=days)
        return self.create_subscription(
            user_id=user_id,
            plan="monthly",
            product="flex",
            payment_provider="trial",
            payment_provider_subscription_id=f"trial-{user_id}-{int(datetime.utcnow().timestamp())}",
            amount=0.0,
            currency="RUB",
            expires_at=expires_at,
            is_trial=True,
            platform="trial",
        )

    def estimate_upgrade_charge(
        self,
        user_id: int,
        target_product: str,
        plan: str = "monthly",
    ) -> Dict[str, Any]:
        """
        Оценка суммы при смене тарифа: полная цена минус прорация неиспользованных дней текущего.
        Новый период (30 дней) начинается после успешной оплаты.
        """
        tier, active = self.effective_tier(user_id)
        target = normalize_tier(target_product)
        full_price = float(self.price_for_product(target, plan))

        base = {
            "full_price": full_price,
            "amount_due": full_price,
            "credit_rub": 0.0,
            "remaining_days": 0,
            "is_upgrade": False,
            "from_tier": tier,
        }
        if not active or tier == "free" or tier == target:
            return base

        user = self.db.query(User).filter(User.id == user_id).first()
        sub = self.get_user_subscription(user_id)
        expires = sub.expires_at if sub else (user.subscription_expires_at if user else None)
        now = datetime.utcnow()
        if not expires or expires <= now:
            return base

        remaining_days = max(0.0, (expires - now).total_seconds() / 86400.0)
        if tier not in TIER_PRICES_RUB:
            return base

        current_monthly = float(TIER_PRICES_RUB[tier]())
        credit = round((current_monthly / 30.0) * remaining_days, 2)
        amount_due = max(round(full_price - credit, 2), 1.0)

        return {
            "full_price": full_price,
            "amount_due": amount_due,
            "credit_rub": credit,
            "remaining_days": int(remaining_days),
            "is_upgrade": True,
            "from_tier": tier,
        }

    @staticmethod
    def price_for_product(product: str, plan: str = "monthly") -> float:
        p = normalize_tier(product)
        if p not in TIER_PRICES_RUB:
            p = "pro"
        if plan == "yearly":
            return TIER_PRICES_RUB[p]() * 10
        return TIER_PRICES_RUB[p]()
