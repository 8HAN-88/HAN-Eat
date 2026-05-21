"""
Кредиты AI scan — мягкие лимиты (backend only, без pressure UX в клиенте).

FREE: 5 при регистрации, +1 / 24h, банк max 5.
AI / Pro: 20 при активации, +10 / 24h, банк max 50.
Creator без AI-сканов.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Optional, Tuple

from sqlalchemy.orm import Session

from app.core.entitlements import tier_includes_ai
from app.models.user import User
from app.services.subscription_service import SubscriptionService

FREE_START = 5
FREE_DAILY = 1
FREE_CAP = 5

PLUS_START = 20
PLUS_DAILY = 10
PLUS_CAP = 50

PLUS_WELCOME_RECONCILE_DAYS = 30


def _naive_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    if getattr(dt, "tzinfo", None) is not None and dt.tzinfo is not None:
        return dt.replace(tzinfo=None)
    return dt


class AiScanCreditsService:
    def __init__(self, db: Session):
        self.db = db

    def is_plus(self, user_id: int) -> bool:
        """AI-лимиты: тариф ai или pro (активная подписка)."""
        return SubscriptionService(self.db).has_ai_access(user_id)

    def _caps(self, is_plus: bool) -> Tuple[int, int, int]:
        if is_plus:
            return PLUS_DAILY, PLUS_CAP, PLUS_START
        return FREE_DAILY, FREE_CAP, FREE_START

    def on_ai_access_activated(self, user_id: int) -> None:
        """Стартовый пакет 20 сканов при оформлении H.A.N. AI или Pro."""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user or not self.is_plus(user_id):
            return
        current = int(user.scan_credits or 0)
        user.scan_credits = min(PLUS_CAP, max(current, PLUS_START))
        user.last_scan_credit_at = datetime.utcnow()
        self.db.commit()

    def reconcile_recent_plus_welcome(self, user: User) -> bool:
        """Подписчик AI/Pro с free-балансом — довести до стартового пакета."""
        if not self.is_plus(user.id):
            return False
        credits = int(user.scan_credits or 0)
        if credits >= PLUS_START:
            return False
        if credits > FREE_CAP:
            return False

        sub = SubscriptionService(self.db).get_user_subscription(user.id)
        if not sub:
            return False
        started = _naive_utc(sub.started_at) or _naive_utc(sub.created_at)
        if not started:
            return False
        if datetime.utcnow() - started > timedelta(days=PLUS_WELCOME_RECONCILE_DAYS):
            return False

        user.scan_credits = min(PLUS_CAP, PLUS_START)
        if user.last_scan_credit_at is None:
            user.last_scan_credit_at = datetime.utcnow()
        return True

    def accrue_if_needed(self, user: User) -> None:
        """Начислить кредиты за полные сутки с last_scan_credit_at."""
        is_plus = self.is_plus(user.id)
        daily, cap, _ = self._caps(is_plus)

        now = datetime.utcnow()
        ref = _naive_utc(user.last_scan_credit_at) or _naive_utc(user.created_at) or now
        delta = now - ref
        days = int(delta.total_seconds() // 86400)
        if days < 1:
            return

        current = int(user.scan_credits or 0)
        user.scan_credits = min(cap, current + days * daily)
        user.last_scan_credit_at = now

    def refresh_user(self, user_id: int) -> User:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise ValueError("user not found")
        self.reconcile_recent_plus_welcome(user)
        self.accrue_if_needed(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def status_meta(self, user: User) -> Dict[str, Any]:
        is_plus = self.is_plus(user.id)
        credits = int(user.scan_credits or 0)
        return {
            "can_scan": credits > 0,
            "soft_warning": (not is_plus) and credits == 1,
            "is_plus": is_plus,
            "subscription_type": user.subscription_type or "free",
        }

    def try_reserve_one_scan(self, user_id: int) -> Tuple[bool, User, Dict[str, Any]]:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise ValueError("user not found")

        self.reconcile_recent_plus_welcome(user)
        self.accrue_if_needed(user)
        meta = self.status_meta(user)
        credits = int(user.scan_credits or 0)

        if credits < 1:
            self.db.commit()
            self.db.refresh(user)
            return False, user, {**meta, "credits_remaining": 0}

        user.scan_credits = credits - 1
        self.db.commit()
        self.db.refresh(user)
        return True, user, {
            **meta,
            "credits_remaining": int(user.scan_credits or 0),
        }


def grant_ai_scan_on_subscription(db: Session, user_id: int, product: str) -> None:
    if tier_includes_ai(product):  # type: ignore[arg-type]
        AiScanCreditsService(db).on_ai_access_activated(user_id)
