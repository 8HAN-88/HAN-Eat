#!/usr/bin/env python3
"""
Тестовые аккаунты персонала: модератор, админ, админ+модератор, админ+Pro.
  cd backend && python3 scripts/create_test_staff_accounts.py

Пароль у всех: HANtest2026!
"""
from __future__ import annotations

import sys
from datetime import datetime, timedelta

sys.path.insert(0, ".")

from app.core.database import SessionLocal
from app.core.security import get_password_hash
from app.models.user import User
from app.services.subscription_service import SubscriptionService

PASSWORD = "HANtest2026!"

# email, label, is_admin, is_moderator, subscription product (None = free)
STAFF = [
    ("han.staff.moderator@haneat.dev", "Модератор", False, True, None),
    ("han.staff.admin@haneat.dev", "Админ", True, False, None),
    ("han.staff.adminmod@haneat.dev", "Админ+Модер", True, True, None),
    ("han.staff.adminpro@haneat.dev", "Админ+Pro", True, False, "pro"),
]


def ensure_staff(
    db,
    email: str,
    name: str,
    *,
    is_admin: bool,
    is_moderator: bool,
) -> User:
    email = email.lower()
    user = db.query(User).filter(User.email == email).first()
    if user:
        user.password_hash = get_password_hash(PASSWORD)
        user.name = name
        user.is_admin = is_admin
        user.is_moderator = is_moderator
        user.banned_at = None
        user.account_warnings = 0
        return user
    username = email.split("@")[0].replace(".", "")[:28]
    user = User(
        email=email,
        password_hash=get_password_hash(PASSWORD),
        name=name,
        username=username,
        subscription_type="free",
        subscription_status="active",
        is_admin=is_admin,
        is_moderator=is_moderator,
    )
    db.add(user)
    db.flush()
    return user


def grant_paid(db, user: User, product: str) -> None:
    svc = SubscriptionService(db)
    expires = datetime.utcnow() + timedelta(days=30)
    prices = {"ai": 199.0, "creator": 499.0, "pro": 649.0}
    svc.create_subscription(
        user_id=user.id,
        plan="monthly",
        product=product,
        payment_provider="dev_test",
        payment_provider_subscription_id=f"dev-staff-{product}-{user.id}",
        amount=prices.get(product, 199.0),
        currency="RUB",
        expires_at=expires,
        platform="dev_test",
    )


def main() -> int:
    db = SessionLocal()
    print("=== HAN Eat — тестовые аккаунты персонала ===\n")
    print(f"Пароль для всех: {PASSWORD}\n")
    print(f"{'Роль':<14} {'Email':<34} admin mod tier")
    print("-" * 72)
    try:
        for email, label, is_admin, is_moder, product in STAFF:
            user = ensure_staff(
                db,
                email,
                label,
                is_admin=is_admin,
                is_moderator=is_moder,
            )
            if product:
                grant_paid(db, user, product)
            db.commit()
            tier, active = SubscriptionService(db).effective_tier(user.id)
            print(
                f"{label:<14} {email:<34} "
                f"{'да' if user.is_admin else '—':<5} "
                f"{'да' if user.is_moderator else '—':<4} "
                f"{tier} ({'active' if active else 'free'})"
            )
        print("\nВ приложении (Настройки):")
        print("  • Модератор / Админ+Модер → «Модерация»")
        print("  • Админ / Админ+Pro / Админ+Модер → «Возвраты подписок» (только is_admin)")
        print("\nBackend: http://127.0.0.1:5001")
        return 0
    except Exception as e:
        db.rollback()
        print(f"ERROR: {e}")
        import traceback

        traceback.print_exc()
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
