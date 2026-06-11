#!/usr/bin/env python3
"""Проверка FIREBASE_* перед включением push на API."""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.config import settings  # noqa: E402
from app.services.push_service import get_push_service  # noqa: E402


def main() -> int:
    errors: list[str] = []

    if not settings.FIREBASE_ENABLED:
        errors.append("FIREBASE_ENABLED=false — задайте true в backend/.env")

    path = (settings.FIREBASE_CREDENTIALS_PATH or "").strip()
    if not path and not os.getenv("FIREBASE_CREDENTIALS_JSON"):
        errors.append(
            "Нет FIREBASE_CREDENTIALS_PATH и FIREBASE_CREDENTIALS_JSON"
        )
    elif path:
        if not os.path.exists(path):
            errors.append(f"Файл credentials не найден: {path}")
        else:
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
                if data.get("type") != "service_account":
                    errors.append("JSON должен быть service account (Firebase Admin)")
                pid = data.get("project_id") or ""
                if settings.FIREBASE_PROJECT_ID and pid != settings.FIREBASE_PROJECT_ID:
                    errors.append(
                        f"project_id в JSON ({pid}) != FIREBASE_PROJECT_ID "
                        f"({settings.FIREBASE_PROJECT_ID})"
                    )
                elif not pid:
                    errors.append("В JSON нет project_id")
                else:
                    print(f"  OK credentials project_id={pid}")
            except json.JSONDecodeError as e:
                errors.append(f"Невалидный JSON: {e}")

    push = get_push_service()
    if push.enabled:
        print("  OK PushService.enabled=true")
    else:
        errors.append("PushService не инициализирован (см. логи API)")

    if errors:
        print("Firebase push NOT ready:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("Firebase push ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
