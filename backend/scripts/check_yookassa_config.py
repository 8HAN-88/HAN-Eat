#!/usr/bin/env python3
"""
Production checklist для ЮKassa (без секретов в выводе).
  cd backend && python3 scripts/check_yookassa_config.py
Exit 0 — готово, 1 — есть проблемы.
"""
from __future__ import annotations

import sys

sys.path.insert(0, ".")

from app.core.config import settings
from app.core.payments_startup import collect_payments_issues


def main() -> int:
    print("=== YooKassa / Payments checklist ===\n")
    print(f"APP_ENV:          {settings.APP_ENV}")
    print(f"YOOKASSA_ENABLED: {settings.YOOKASSA_ENABLED}")
    print(f"FRONTEND_URL:     {settings.FRONTEND_URL}")
    print(f"API_PUBLIC_BASE:  {settings.API_PUBLIC_BASE_URL}")
    webhook = (
        f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}"
        "/api/v1/payments/webhook/yookassa"
    )
    print(f"\nWebhook URL (ЛК ЮKassa):\n  {webhook}\n")
    print("Тарифы RUB:")
    print(f"  AI:      {settings.AI_MONTHLY_PRICE_RUB}")
    print(f"  Creator: {settings.CREATOR_MONTHLY_PRICE_RUB}")
    print(f"  Pro:     {settings.PRO_MONTHLY_PRICE_RUB}")
    print(f"\nОкно запроса возврата: {settings.SUBSCRIPTION_REFUND_REQUEST_DAYS} дн.\n")

    issues = collect_payments_issues()
    if issues:
        print("ISSUES:")
        for i, msg in enumerate(issues, 1):
            print(f"  {i}. {msg}")
        print("\nFAIL: исправьте конфигурацию (.env) перед production.")
        return 1

    print("OK: конфигурация платежей выглядит готовой.")
    print("\nРучной чеклист:")
    print("  [ ] Webhook URL зарегистрирован в ЮKassa (HTTPS, не localhost)")
    print("  [ ] 54-ФЗ чеки включены в ЛК, email покупателя передаётся")
    print("  [ ] Тестовый платёж → webhook → подписка active в /subscriptions/status")
    return 0


if __name__ == "__main__":
    sys.exit(main())
