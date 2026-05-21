#!/usr/bin/env python3
"""
Выдать AI scan кредиты пользователю (dev/support).
  python3 backend/scripts/grant_ai_scan_credits.py user@email.com 5
"""
from __future__ import annotations

import sys
from datetime import datetime

# noqa: E402 — run from repo root or backend/
sys.path.insert(0, ".")

from app.core.database import SessionLocal
from app.models.user import User
from app.services.ai_scan_credits_service import FREE_CAP, PLUS_CAP, AiScanCreditsService


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: grant_ai_scan_credits.py <email> <credits>")
        return 1
    email = sys.argv[1].strip().lower()
    try:
        amount = int(sys.argv[2])
    except ValueError:
        print("credits must be an integer")
        return 1
    if amount < 0:
        print("credits must be >= 0")
        return 1

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            print(f"User not found: {email}")
            return 1
        svc = AiScanCreditsService(db)
        cap = PLUS_CAP if svc.is_plus(user.id) else FREE_CAP
        user.scan_credits = min(amount, cap)
        user.last_scan_credit_at = datetime.utcnow()
        db.commit()
        db.refresh(user)
        print(f"OK {email} (id={user.id}) scan_credits={user.scan_credits} (cap={cap})")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
