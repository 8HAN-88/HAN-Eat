"""Отправка транзакционных писем (SMTP). В dev без SMTP — лог в консоль."""
from __future__ import annotations

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

from app.core.config import settings

logger = logging.getLogger(__name__)


def email_delivery_configured() -> bool:
    return bool(settings.EMAIL_SMTP_HOST and settings.EMAIL_FROM)


def send_transactional_email(
    to_email: str,
    subject: str,
    text_body: str,
    html_body: Optional[str] = None,
) -> bool:
    """Возвращает True, если письмо отправлено или залогировано в dev."""
    if not to_email:
        return False

    if not email_delivery_configured():
        logger.warning(
            "EMAIL not configured — letter to %s | %s\n%s",
            to_email,
            subject,
            text_body,
        )
        return settings.APP_ENV != "production"

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = (
        f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM}>"
        if settings.EMAIL_FROM_NAME
        else settings.EMAIL_FROM
    )
    msg["To"] = to_email
    msg.attach(MIMEText(text_body, "plain", "utf-8"))
    if html_body:
        msg.attach(MIMEText(html_body, "html", "utf-8"))

    user = (settings.EMAIL_SMTP_USER or "").strip()
    password = (settings.EMAIL_SMTP_PASSWORD or "").strip()

    try:
        if settings.EMAIL_SMTP_USE_SSL:
            server = smtplib.SMTP_SSL(
                settings.EMAIL_SMTP_HOST,
                settings.EMAIL_SMTP_PORT,
                timeout=30,
            )
        else:
            server = smtplib.SMTP(
                settings.EMAIL_SMTP_HOST,
                settings.EMAIL_SMTP_PORT,
                timeout=30,
            )
            if settings.EMAIL_SMTP_USE_TLS:
                server.starttls()
        if user and password:
            server.login(user, password)
        server.sendmail(settings.EMAIL_FROM, [to_email], msg.as_string())
        server.quit()
        logger.info("Email sent to %s: %s", to_email, subject)
        return True
    except Exception as e:
        logger.error("Failed to send email to %s: %s", to_email, e, exc_info=True)
        return False
