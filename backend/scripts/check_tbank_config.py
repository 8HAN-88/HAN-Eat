#!/usr/bin/env python3
"""
Production checklist для Т-Банка (без секретов в выводе).
  cd backend && python3 scripts/check_tbank_config.py
Exit 0 — готово, 1 — есть проблемы.
"""
from __future__ import annotations

import sys

sys.path.insert(0, ".")

from app.core.config import settings
from app.core.payments_startup import collect_payments_issues


def main() -> int:
    print("=== T-Bank / Payments checklist ===\n")
    print(f"APP_ENV:                 {settings.APP_ENV}")
    print(f"TBANK_ENABLED:           {settings.TBANK_ENABLED}")
    print(f"TBANK_SBP_RECURRING:     {settings.TBANK_SBP_RECURRING_ENABLED}")
    print(f"YOOKASSA_ENABLED:        {settings.YOOKASSA_ENABLED}")
    print(f"FRONTEND_URL:            {settings.FRONTEND_URL}")
    print(f"API_PUBLIC_BASE:         {settings.API_PUBLIC_BASE_URL}")
    webhook = (
        f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}"
        "/api/v1/payments/webhook/tbank"
    )
    print(f"\nWebhook URL (ЛК Т-Банк):\n  {webhook}\n")
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
    print("  [ ] Webhook URL зарегистрирован в ЛК Т-Банка (HTTPS)")
    print("  [ ] В терминале включены СБП и рекуррентные платежи")
    print("  [ ] Тестовый Init → оплата СБП → webhook CONFIRMED → подписка active")
    print("  [ ] RebillId сохранён в users.tbank_rebill_id после первой оплаты")
    return 0


if __name__ == "__main__":
    sys.exit(main())
