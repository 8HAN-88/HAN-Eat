#!/usr/bin/env python3
"""
Назначить пользователя администратором (для панели возвратов и др.).
  cd backend && python3 scripts/grant_admin.py user@email.com
"""
from __future__ import annotations

import sys

sys.path.insert(0, ".")

from app.core.database import SessionLocal
from app.models.user import User


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: grant_admin.py <email>")
        return 1
    email = sys.argv[1].strip().lower()

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            print(f"User not found: {email}")
            return 1
        user.is_admin = True
        db.commit()
        print(f"OK {email} (id={user.id}) is_admin=True")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
