#!/usr/bin/env python3
"""
Проверка SMTP для писем (регистрация, сброс пароля).
  cd backend && source venv/bin/activate && python3 scripts/check_email_config.py
  python3 scripts/check_email_config.py --probe
  python3 scripts/check_email_config.py --send-test you@gmail.com
Exit 0 — OK, 1 — есть проблемы.
"""
from __future__ import annotations

import argparse
import smtplib
import sys

sys.path.insert(0, ".")

from app.core.config import settings
from app.services.email_delivery_service import (
    email_delivery_configured,
    send_transactional_email,
)


def collect_email_issues() -> list[str]:
    issues: list[str] = []
    provider = (settings.EMAIL_PROVIDER or "smtp").strip().lower()
    if provider == "resend":
        if not (settings.RESEND_API_KEY or "").strip():
            issues.append("RESEND_API_KEY не задан (resend.com → API Keys)")
        if not settings.EMAIL_FROM:
            issues.append("EMAIL_FROM не задан (отправитель для Resend)")
        return issues

    if not settings.EMAIL_SMTP_HOST:
        issues.append("EMAIL_SMTP_HOST не задан")
    if not settings.EMAIL_FROM:
        issues.append("EMAIL_FROM не задан (должен совпадать с ящиком Яндекса)")
    if not settings.EMAIL_SMTP_USER:
        issues.append("EMAIL_SMTP_USER не задан")
    pwd = (settings.EMAIL_SMTP_PASSWORD or "").strip()
    if not pwd:
        issues.append("EMAIL_SMTP_PASSWORD не задан (пароль приложения Яндекса)")
    elif len(pwd) < 16:
        issues.append(
            f"EMAIL_SMTP_PASSWORD слишком короткий ({len(pwd)} симв.) — "
            "пароль приложения Яндекса обычно 16+ символов без пробелов"
        )
    if settings.EMAIL_FROM and settings.EMAIL_SMTP_USER:
        if settings.EMAIL_FROM.lower() != settings.EMAIL_SMTP_USER.lower():
            issues.append(
                "EMAIL_FROM и EMAIL_SMTP_USER должны быть одним и тем же адресом "
                f"({settings.EMAIL_FROM} vs {settings.EMAIL_SMTP_USER})"
            )
    return issues


def _try_smtp_login(
    host: str,
    port: int,
    *,
    use_ssl: bool,
    use_tls: bool,
    login_user: str,
    password: str,
) -> tuple[bool, str]:
    try:
        if use_ssl:
            server = smtplib.SMTP_SSL(host, port, timeout=25)
        else:
            server = smtplib.SMTP(host, port, timeout=25)
            if use_tls:
                server.starttls()
        server.login(login_user, password)
        server.quit()
        return True, "OK"
    except Exception as e:
        return False, str(e)


def run_probe() -> int:
    pwd = (settings.EMAIL_SMTP_PASSWORD or "").strip()
    email = (settings.EMAIL_SMTP_USER or "").strip()
    if not email or not pwd:
        print("FAIL: задайте EMAIL_SMTP_USER и EMAIL_SMTP_PASSWORD в .env")
        return 1

    local = email.split("@", 1)[0] if "@" in email else email
    logins = [email]
    if local != email:
        logins.append(local)

    combos = [
        ("smtp.yandex.com", 465, True, False),
        ("smtp.yandex.ru", 465, True, False),
        ("smtp.yandex.com", 587, False, True),
        ("smtp.yandex.ru", 587, False, True),
    ]

    print("=== SMTP probe (только login, без отправки письма) ===\n")
    print(f"EMAIL из .env:     {email}")
    print(f"длина пароля:      {len(pwd)} символов\n")

    any_ok = False
    for host, port, ssl, tls in combos:
        for login in logins:
            ok, msg = _try_smtp_login(
                host,
                port,
                use_ssl=ssl,
                use_tls=tls,
                login_user=login,
                password=pwd,
            )
            mode = "SSL" if ssl else "STARTTLS"
            status = "OK" if ok else "FAIL"
            print(f"[{status}] {host}:{port} {mode} login={login!r}")
            if not ok:
                short = msg.replace("\n", " ")[:120]
                print(f"       {short}")
            else:
                any_ok = True
                print(
                    f"\n>>> Рабочая связка. Пропишите в .env:\n"
                    f"EMAIL_SMTP_HOST={host}\n"
                    f"EMAIL_SMTP_PORT={port}\n"
                    f"EMAIL_SMTP_USE_SSL={'true' if ssl else 'false'}\n"
                    f"EMAIL_SMTP_USE_TLS={'true' if tls else 'false'}\n"
                    f"EMAIL_SMTP_USER={email}\n"
                )
                return 0

    print(
        "\nНи одна связка не подошла.\n"
        "Частые причины 535 «does not have access rights»:\n"
        "  1) В .env не пароль приложения «Почта», а пароль от входа на Яндекс\n"
        "  2) Пароль приложения создан в другом аккаунте (проверьте логин на id.yandex.ru)\n"
        "  3) В mail.yandex.ru → Почтовые программы не выбраны «Пароли приложений»\n"
        "  4) Адрес в .env не совпадает с ящиком (проверьте @yandex.ru / @ya.ru в углу почты)\n"
        "  5) Удалите старые пароли приложений → создайте один новый «Почта» → вставьте без пробелов\n"
    )
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--send-test",
        metavar="EMAIL",
        help="Отправить тестовое письмо на указанный адрес",
    )
    parser.add_argument(
        "--probe",
        action="store_true",
        help="Перебор smtp.yandex.com/ru и портов 465/587 (только login)",
    )
    args = parser.parse_args()

    if args.probe:
        if (settings.EMAIL_PROVIDER or "smtp").strip().lower() == "resend":
            print("EMAIL_PROVIDER=resend — SMTP probe не нужен, используйте --send-test")
            return 0
        return run_probe()

    print("=== Email / SMTP checklist ===\n")
    pwd = (settings.EMAIL_SMTP_PASSWORD or "").strip()
    print(f"APP_ENV:              {settings.APP_ENV}")
    print(f"EMAIL_PROVIDER:       {settings.EMAIL_PROVIDER or 'smtp'}")
    print(f"RESEND_API_KEY set:   {bool((settings.RESEND_API_KEY or '').strip())}")
    print(f"AUTH_LINK_BASE_URL:   {settings.AUTH_LINK_BASE_URL}")
    print(f"EMAIL_SMTP_HOST:      {settings.EMAIL_SMTP_HOST or '(пусто)'}")
    print(f"EMAIL_SMTP_PORT:      {settings.EMAIL_SMTP_PORT}")
    print(f"EMAIL_SMTP_USE_SSL:   {settings.EMAIL_SMTP_USE_SSL}")
    print(f"EMAIL_SMTP_USE_TLS:   {settings.EMAIL_SMTP_USE_TLS}")
    print(f"EMAIL_SMTP_USER:      {settings.EMAIL_SMTP_USER or '(пусто)'}")
    print(f"EMAIL_FROM:           {settings.EMAIL_FROM or '(пусто)'}")
    print(f"configured:           {email_delivery_configured()}")
    print(f"password length:      {len(pwd) if pwd else 0}\n")

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
        print(
            "FAIL: отправка не удалась.\n"
            "Запустите: python3 scripts/check_email_config.py --probe"
        )
        return 1

    print("Подсказки:")
    print("  python3 scripts/check_email_config.py --probe")
    print("  python3 scripts/check_email_config.py --send-test your@email.com")
    return 0


if __name__ == "__main__":
    sys.exit(main())
