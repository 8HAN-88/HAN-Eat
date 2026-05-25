"""Отправка транзакционных писем: SMTP или Resend HTTP API."""
from __future__ import annotations

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


def _from_header() -> str:
    if settings.EMAIL_FROM_NAME and settings.EMAIL_FROM:
        return f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM}>"
    return settings.EMAIL_FROM or ""


def email_delivery_configured() -> bool:
    provider = (settings.EMAIL_PROVIDER or "smtp").strip().lower()
    if provider == "resend":
        return bool(settings.RESEND_API_KEY and settings.EMAIL_FROM)
    return bool(settings.EMAIL_SMTP_HOST and settings.EMAIL_FROM)


def _send_via_resend(
    to_email: str,
    subject: str,
    text_body: str,
    html_body: Optional[str],
) -> bool:
    payload: dict = {
        "from": _from_header(),
        "to": [to_email],
        "subject": subject,
        "text": text_body,
    }
    if html_body:
        payload["html"] = html_body

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {settings.RESEND_API_KEY.strip()}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
        if resp.status_code in (200, 201):
            logger.info("Resend: email sent to %s: %s", to_email, subject)
            return True
        logger.error(
            "Resend failed %s for %s: %s",
            resp.status_code,
            to_email,
            resp.text[:500],
        )
        return False
    except Exception as e:
        logger.error("Resend error for %s: %s", to_email, e, exc_info=True)
        return False


def _send_via_smtp(
    to_email: str,
    subject: str,
    text_body: str,
    html_body: Optional[str],
) -> bool:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = _from_header()
    msg["To"] = to_email
    msg.attach(MIMEText(text_body, "plain", "utf-8"))
    if html_body:
        msg.attach(MIMEText(html_body, "html", "utf-8"))

    user = (settings.EMAIL_SMTP_USER or "").strip()
    password = (settings.EMAIL_SMTP_PASSWORD or "").strip()

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
    logger.info("SMTP: email sent to %s: %s", to_email, subject)
    return True


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

    provider = (settings.EMAIL_PROVIDER or "smtp").strip().lower()
    try:
        if provider == "resend":
            return _send_via_resend(to_email, subject, text_body, html_body)
        return _send_via_smtp(to_email, subject, text_body, html_body)
    except Exception as e:
        logger.error("Failed to send email to %s: %s", to_email, e, exc_info=True)
        return False
