#!/usr/bin/env python3
"""
Создать тестовые аккаунты по тарифам (для ручного QA на симуляторе).
  cd backend && python3 scripts/create_test_accounts.py

Пароль у всех один: HANtest2026!
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
ACCOUNTS = [
    ("han.test.free@haneat.dev", "free", None, "Тест Free"),
    ("han.test.ai@haneat.dev", "ai", "ai", "Тест AI"),
    ("han.test.creator@haneat.dev", "creator", "creator", "Тест Creator"),
    ("han.test.pro@haneat.dev", "pro", "pro", "Тест Pro"),
]


def ensure_user(db, email: str, name: str) -> User:
    user = db.query(User).filter(User.email == email.lower()).first()
    if user:
        user.password_hash = get_password_hash(PASSWORD)
        user.name = name
        user.subscription_type = "free"
        user.subscription_status = "active"
        user.subscription_expires_at = None
        user.is_admin = False
        user.is_moderator = False
        return user
    username = email.split("@")[0].replace(".", "")[:28]
    user = User(
        email=email.lower(),
        password_hash=get_password_hash(PASSWORD),
        name=name,
        username=username,
        subscription_type="free",
        subscription_status="active",
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
        payment_provider_subscription_id=f"dev-test-{product}-{user.id}",
        amount=prices.get(product, 199.0),
        currency="RUB",
        expires_at=expires,
        platform="dev_test",
    )


def main() -> int:
    db = SessionLocal()
    print("=== HAN Eat — тестовые аккаунты ===\n")
    print(f"Пароль для всех: {PASSWORD}\n")
    print(f"{'Тариф':<10} {'Email':<32} {'Статус'}")
    print("-" * 60)
    try:
        for email, label, product, name in ACCOUNTS:
            user = ensure_user(db, email, name)
            if product:
                grant_paid(db, user, product)
                db.refresh(user)
            db.commit()
            tier, active = SubscriptionService(db).effective_tier(user.id)
            flags = []
            if SubscriptionService(db).has_ai_access(user.id):
                flags.append("AI")
            if SubscriptionService(db).has_creator_access(user.id):
                flags.append("Creator")
            print(f"{label:<10} {email:<32} {tier} active={active} [{', '.join(flags) or '—'}]")
        print("\nBackend: http://127.0.0.1:5001")
        print("В приложении: войти по email + пароль выше.")
        return 0
    except Exception as e:
        db.rollback()
        print(f"ERROR: {e}")
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
