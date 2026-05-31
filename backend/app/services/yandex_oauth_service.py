"""Яндекс ID OAuth 2.0 (опционально; email-вход работает без этого)."""
from __future__ import annotations

import logging
from typing import Any
from urllib.parse import urlencode

import httpx
from fastapi import HTTPException, status

from app.core.config import settings

logger = logging.getLogger(__name__)

YANDEX_AUTHORIZE_URL = "https://oauth.yandex.ru/authorize"
YANDEX_TOKEN_URL = "https://oauth.yandex.ru/token"
YANDEX_USERINFO_URL = "https://login.yandex.ru/info"


def yandex_oauth_configured() -> bool:
    return bool(
        (settings.YANDEX_OAUTH_CLIENT_ID or "").strip()
        and (settings.YANDEX_OAUTH_CLIENT_SECRET or "").strip()
    )


def build_authorize_url(*, redirect_uri: str) -> str:
    params = {
        "response_type": "code",
        "client_id": settings.YANDEX_OAUTH_CLIENT_ID.strip(),
        "redirect_uri": redirect_uri.strip(),
    }
    return f"{YANDEX_AUTHORIZE_URL}?{urlencode(params)}"


async def exchange_code_and_fetch_profile(
    code: str,
    redirect_uri: str,
) -> dict[str, Any]:
    if not yandex_oauth_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Yandex OAuth is not configured",
        )

    async with httpx.AsyncClient() as client:
        token_resp = await client.post(
            YANDEX_TOKEN_URL,
            data={
                "grant_type": "authorization_code",
                "code": code.strip(),
                "client_id": settings.YANDEX_OAUTH_CLIENT_ID.strip(),
                "client_secret": settings.YANDEX_OAUTH_CLIENT_SECRET.strip(),
                "redirect_uri": redirect_uri.strip(),
            },
            timeout=20.0,
        )
        if token_resp.status_code != 200:
            logger.warning("Yandex token error: %s %s", token_resp.status_code, token_resp.text)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Yandex token exchange failed",
            )
        token_data = token_resp.json()
        access_token = token_data.get("access_token")
        if not access_token:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Yandex token response missing access_token",
            )

        info_resp = await client.get(
            YANDEX_USERINFO_URL,
            params={"format": "json"},
            headers={"Authorization": f"OAuth {access_token}"},
            timeout=15.0,
        )
        if info_resp.status_code != 200:
            logger.warning("Yandex userinfo error: %s", info_resp.text)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Failed to fetch Yandex profile",
            )
        info = info_resp.json()

    email = info.get("default_email") or (info.get("emails") or [None])[0]
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Yandex account has no email",
        )
    name = (
        info.get("display_name")
        or info.get("real_name")
        or info.get("login")
        or "Yandex User"
    )
    return {"email": str(email).strip().lower(), "name": str(name).strip()}
