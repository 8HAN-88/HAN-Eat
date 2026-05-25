#!/usr/bin/env python3
"""
Проверка SMTP для писем (регистрация, сброс пароля).
  cd backend && source venv/bin/activate && python3 scripts/check_email_config.py
  cd backend && python3 scripts/check_email_config.py --send-test you@gmail.com
Exit 0 — OK, 1 — есть проблемы.
"""
from __future__ import annotations

import argparse
import sys

sys.path.insert(0, ".")

from app.core.config import settings
from app.services.email_delivery_service import (
    email_delivery_configured,
    send_transactional_email,
)


def collect_email_issues() -> list[str]:
    issues: list[str] = []
    if not settings.EMAIL_SMTP_HOST:
        issues.append("EMAIL_SMTP_HOST не задан")
    if not settings.EMAIL_FROM:
        issues.append("EMAIL_FROM не задан (должен совпадать с ящиком Яндекса)")
    if not settings.EMAIL_SMTP_USER:
        issues.append("EMAIL_SMTP_USER не задан")
    if not settings.EMAIL_SMTP_PASSWORD:
        issues.append("EMAIL_SMTP_PASSWORD не задан (пароль приложения Яндекса)")
    if settings.EMAIL_FROM and settings.EMAIL_SMTP_USER:
        if settings.EMAIL_FROM.lower() != settings.EMAIL_SMTP_USER.lower():
            issues.append(
                "EMAIL_FROM и EMAIL_SMTP_USER должны быть одним и тем же адресом "
                f"({settings.EMAIL_FROM} vs {settings.EMAIL_SMTP_USER})"
            )
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--send-test",
        metavar="EMAIL",
        help="Отправить тестовое письмо на указанный адрес",
    )
    args = parser.parse_args()

    print("=== Email / SMTP checklist ===\n")
    print(f"APP_ENV:              {settings.APP_ENV}")
    print(f"AUTH_LINK_BASE_URL:   {settings.AUTH_LINK_BASE_URL}")
    print(f"EMAIL_SMTP_HOST:      {settings.EMAIL_SMTP_HOST or '(пусто)'}")
    print(f"EMAIL_SMTP_PORT:      {settings.EMAIL_SMTP_PORT}")
    print(f"EMAIL_SMTP_USER:      {settings.EMAIL_SMTP_USER or '(пусто)'}")
    print(f"EMAIL_FROM:           {settings.EMAIL_FROM or '(пусто)'}")
    print(f"configured:           {email_delivery_configured()}")
    print(f"password set:         {bool(settings.EMAIL_SMTP_PASSWORD)}\n")

    issues = collect_email_issues()
    if issues:
        print("ISSUES:")
        for i, msg in enumerate(issues, 1):
            print(f"  {i}. {msg}")
        print("\nFAIL: допишите backend/.env и: systemctl restart haneat-api")
        return 1

    print("OK: переменные SMTP заданы.\n")

    if args.send_test:
        to = args.send_test.strip()
        print(f"Отправка теста на {to} ...")
        ok = send_transactional_email(
            to,
            "HAN Eat — тест SMTP",
            "Если вы видите это письмо, SMTP настроен правильно.",
            "<p>Если вы видите это письмо, <strong>SMTP настроен правильно</strong>.</p>",
        )
        if ok:
            print("OK: письмо отправлено (проверьте входящие и «Спам»).")
            return 0
        print("FAIL: send_transactional_email вернул False — смотрите journalctl -u haneat-api")
        return 1

    print("Подсказка: python3 scripts/check_email_config.py --send-test your@email.com")
    return 0


if __name__ == "__main__":
    sys.exit(main())
