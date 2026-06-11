#!/usr/bin/env python3
"""
Создать все тестовые аккаунты: тарифы + персонал (модераторы, админы).
  cd backend && python3 scripts/create_all_test_accounts.py

Пароль у всех: HANtest2026!
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent


def main() -> int:
    scripts = [
        BACKEND / "scripts" / "create_test_accounts.py",
        BACKEND / "scripts" / "create_test_staff_accounts.py",
    ]
    code = 0
    for script in scripts:
        print(f"\n{'=' * 60}\n>>> {script.name}\n{'=' * 60}")
        r = subprocess.run([sys.executable, str(script)], cwd=str(BACKEND))
        if r.returncode != 0:
            code = r.returncode
    if code == 0:
        print(f"\n{'=' * 60}")
        print("Готово. Список аккаунтов: backend/docs/TEST_ACCOUNTS.md")
        print(f"{'=' * 60}")
    return code


if __name__ == "__main__":
    sys.exit(main())
