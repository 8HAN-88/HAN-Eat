"""
Фоновые задачи подписок: grace period, напоминания об окончании.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.notification import Notification
from app.models.user import User
from app.services.notification_service import NotificationService
from app.services.subscription_service import SubscriptionService

_BATCH = 100


class SubscriptionMaintenanceService:
    def __init__(self, db: Session):
        self.db = db

    def run(self) -> None:
        self._expire_after_grace()
        self._notify_expiring()

    def _grace_delta(self) -> timedelta:
        return timedelta(days=int(settings.SUBSCRIPTION_GRACE_PERIOD_DAYS or 3))

    def _expire_after_grace(self) -> int:
        now = datetime.utcnow()
        cutoff = now - self._grace_delta()
        expired = 0
        svc = SubscriptionService(self.db)
        while True:
            users = (
                self.db.query(User)
                .filter(
                    User.subscription_type.notin_(("free",)),
                    User.subscription_expires_at.isnot(None),
                    User.subscription_expires_at < cutoff,
                )
                .limit(_BATCH)
                .all()
            )
            if not users:
                break
            for user in users:
                tier, _active = svc.effective_tier(user.id)
                if tier == "free":
                    continue
                sub = svc.get_user_subscription(user.id)
                if sub:
                    svc.expire_subscription(sub.id)
                else:
                    user.subscription_type = "free"
                    user.subscription_status = "expired"
                    user.subscription_expires_at = None
                    user.subscription_auto_renew = False
                try:
                    NotificationService(self.db).create_notification(
                        user_id=user.id,
                        type="subscription_expired",
                        title="Подписка завершена",
                        body=(
                            "Срок подписки истёк. Оформите тариф снова "
                            "в разделе «Подписка»."
                        ),
                        entity_type="subscription",
                        entity_id=0,
                        data={"route": "subscription"},
                    )
                except Exception:
                    pass
                expired += 1
            self.db.flush()
        return expired

    def _already_notified(self, user_id: int, key: str) -> bool:
        since = datetime.utcnow() - timedelta(days=8)
        rows = (
            self.db.query(Notification)
            .filter(
                Notification.user_id == user_id,
                Notification.type == "subscription_expiring",
                Notification.created_at >= since,
            )
            .all()
        )
        for n in rows:
            data = n.data if isinstance(n.data, dict) else {}
            if data.get("reminder_key") == key:
                return True
        return False

    def _notify_expiring(self) -> int:
        now = datetime.utcnow()
        sent = 0
        for days_left in (3, 1):
            window_end = now + timedelta(days=days_left)
            window_start = now + timedelta(days=days_left - 1)
            offset = 0
            while True:
                users = (
                    self.db.query(User)
                    .filter(
                        User.subscription_type.notin_(("free",)),
                        User.subscription_expires_at.isnot(None),
                        User.subscription_expires_at > window_start,
                        User.subscription_expires_at <= window_end,
                    )
                    .offset(offset)
                    .limit(_BATCH)
                    .all()
                )
                if not users:
                    break
                for user in users:
                    key = (
                        f"{user.id}:{days_left}:"
                        f"{user.subscription_expires_at.date()}"
                    )
                    if self._already_notified(user.id, key):
                        continue
                    NotificationService(self.db).create_notification(
                        user_id=user.id,
                        type="subscription_expiring",
                        title="Подписка скоро закончится",
                        body=(
                            f"Ваша подписка H.A.N. истекает через {days_left} дн. "
                            "Продлите в разделе «Подписка», чтобы сохранить доступ."
                        ),
                        entity_type="subscription",
                        entity_id=0,
                        data={
                            "reminder_key": key,
                            "days_left": days_left,
                            "route": "subscription",
                        },
                    )
                    sent += 1
                offset += len(users)
                if len(users) < _BATCH:
                    break
        return sent
