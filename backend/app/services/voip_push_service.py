"""Apple PushKit VoIP pushes for CallKit (iOS killed / locked).

Regular FCM/APNs cannot wake a killed iOS app into CallKit — only a VoIP push
to topic `{bundle_id}.voip` with `apns-push-type: voip` works.
"""
from __future__ import annotations

import json
import logging
import os
import time
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.user import User

logger = logging.getLogger(__name__)

_jwt_cache: dict[str, Any] = {"token": None, "exp": 0.0}


def _auth_key_pem() -> Optional[str]:
    raw = (getattr(settings, "APNS_AUTH_KEY", None) or "").strip()
    if raw:
        return raw.replace("\\n", "\n")
    path = (getattr(settings, "APNS_AUTH_KEY_PATH", None) or "").strip()
    if path and os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    return None


def voip_push_configured() -> bool:
    key_id = (getattr(settings, "APNS_KEY_ID", None) or "").strip()
    team_id = (getattr(settings, "APNS_TEAM_ID", None) or "").strip()
    bundle = (getattr(settings, "APNS_BUNDLE_ID", None) or "").strip()
    return bool(key_id and team_id and bundle and _auth_key_pem())


def build_apns_jwt(*, now: Optional[float] = None, force: bool = False) -> str:
    """ES256 JWT for APNs (cached ~45 minutes)."""
    now_ts = now if now is not None else time.time()
    if (
        not force
        and _jwt_cache["token"]
        and now_ts < float(_jwt_cache["exp"]) - 60
    ):
        return str(_jwt_cache["token"])

    from jose import jwt

    key_id = (settings.APNS_KEY_ID or "").strip()
    team_id = (settings.APNS_TEAM_ID or "").strip()
    pem = _auth_key_pem()
    if not key_id or not team_id or not pem:
        raise RuntimeError("APNs VoIP credentials are not configured")

    token = jwt.encode(
        {"iss": team_id, "iat": int(now_ts)},
        pem,
        algorithm="ES256",
        headers={"alg": "ES256", "kid": key_id},
    )
    if isinstance(token, bytes):
        token = token.decode("ascii")
    _jwt_cache["token"] = token
    _jwt_cache["exp"] = now_ts + 45 * 60
    return token


def build_voip_payload(
    *,
    call_id: int,
    caller_name: str,
    media: str = "voice",
    conversation_id: Optional[int] = None,
    caller_avatar: Optional[str] = None,
    call_kind: str = "direct",
    action: str = "incoming",
) -> dict[str, Any]:
    """Payload shape expected by ios/Runner/AppDelegate.swift PushKit handler."""
    data: dict[str, Any] = {
        "type": "call.ended" if action == "end" else "call.incoming",
        "route": "call",
        "action": action,
        "call_id": str(call_id),
        "media": media or "voice",
        "caller_name": caller_name or "Звонок",
        "call_kind": call_kind or "direct",
    }
    if conversation_id is not None:
        data["conversation_id"] = str(conversation_id)
    if caller_avatar:
        data["caller_avatar"] = caller_avatar
    return {
        "aps": {"content-available": 1},
        "data": data,
        # Flat mirrors for defensive parsing.
        **data,
    }


def _apns_host() -> str:
    if bool(getattr(settings, "APNS_USE_SANDBOX", False)):
        return "api.sandbox.push.apple.com"
    return "api.push.apple.com"


def send_voip_push(
    device_token: str,
    payload: dict[str, Any],
    *,
    expiration: Optional[int] = None,
) -> tuple[bool, Optional[int], Optional[str]]:
    """
    POST VoIP notification to APNs.

    Returns (ok, status_code, reason).
    """
    token = (device_token or "").strip().replace(" ", "")
    if not token:
        return False, None, "empty_token"
    if not voip_push_configured():
        logger.debug("VoIP APNs not configured; skip")
        return False, None, "not_configured"

    try:
        import httpx
    except ImportError:
        logger.error("httpx not installed; cannot send VoIP push")
        return False, None, "httpx_missing"

    bundle = (settings.APNS_BUNDLE_ID or "com.haneat.app").strip()
    topic = f"{bundle}.voip"
    url = f"https://{_apns_host()}/3/device/{token}"
    headers = {
        "authorization": f"bearer {build_apns_jwt()}",
        "apns-topic": topic,
        "apns-push-type": "voip",
        "apns-priority": "10",
        "content-type": "application/json",
    }
    if expiration is not None:
        headers["apns-expiration"] = str(int(expiration))

    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    try:
        with httpx.Client(http2=True, timeout=10.0) as client:
            resp = client.post(url, content=body, headers=headers)
    except Exception as e:
        logger.error("VoIP APNs request failed: %s", e, exc_info=True)
        return False, None, str(e)

    if resp.status_code == 200:
        return True, 200, None

    reason = None
    try:
        reason = (resp.json() or {}).get("reason")
    except Exception:
        reason = resp.text[:200] if resp.text else None
    logger.warning(
        "VoIP APNs rejected token (...%s): %s %s",
        token[-8:],
        resp.status_code,
        reason,
    )
    return False, resp.status_code, reason


def clear_invalid_voip_token(db: Session, user_id: int) -> None:
    user = db.query(User).filter(User.id == user_id).first()
    if user and user.voip_token:
        user.voip_token = None
        db.flush()
        logger.info("Cleared invalid voip_token for user %s", user_id)


def send_call_voip_to_user(
    db: Session,
    user: User,
    *,
    call_id: int,
    caller_name: str,
    media: str = "voice",
    conversation_id: Optional[int] = None,
    caller_avatar: Optional[str] = None,
    call_kind: str = "direct",
    action: str = "incoming",
    ring_timeout_seconds: int = 60,
) -> bool:
    """Send incoming or end VoIP push; clear token on Unregistered/BadDeviceToken."""
    token = (getattr(user, "voip_token", None) or "").strip()
    if not token:
        return False
    if not voip_push_configured():
        return False

    exp = int(time.time()) + max(15, int(ring_timeout_seconds or 60))
    payload = build_voip_payload(
        call_id=call_id,
        caller_name=caller_name,
        media=media,
        conversation_id=conversation_id,
        caller_avatar=caller_avatar,
        call_kind=call_kind,
        action=action,
    )
    ok, status, reason = send_voip_push(token, payload, expiration=exp)
    if ok:
        return True
    if status in (400, 410) and reason in (
        "BadDeviceToken",
        "Unregistered",
        "DeviceTokenNotForTopic",
        "ExpiredToken",
    ):
        try:
            clear_invalid_voip_token(db, user.id)
        except Exception:
            logger.exception("Failed clearing voip_token for user %s", user.id)
    return False


class VoipPushService:
    """Thin façade used by PushService / CallService."""

    def send_incoming(self, db: Session, user: User, data: dict[str, Any]) -> bool:
        call_id = data.get("call_id")
        try:
            call_id_int = int(call_id)
        except (TypeError, ValueError):
            return False
        conv = data.get("conversation_id")
        try:
            conv_id = int(conv) if conv is not None and str(conv) != "" else None
        except (TypeError, ValueError):
            conv_id = None
        from app.services.call_service import ring_timeout_seconds

        return send_call_voip_to_user(
            db,
            user,
            call_id=call_id_int,
            caller_name=str(data.get("caller_name") or data.get("title") or "Звонок"),
            media=str(data.get("media") or "voice"),
            conversation_id=conv_id,
            caller_avatar=(str(data["caller_avatar"]) if data.get("caller_avatar") else None),
            call_kind=str(data.get("call_kind") or "direct"),
            action="incoming",
            ring_timeout_seconds=ring_timeout_seconds(),
        )

    def send_end(self, db: Session, user: User, *, call_id: int, media: str = "voice") -> bool:
        return send_call_voip_to_user(
            db,
            user,
            call_id=call_id,
            caller_name="Звонок",
            media=media,
            action="end",
            ring_timeout_seconds=30,
        )


_voip_service: Optional[VoipPushService] = None


def get_voip_push_service() -> VoipPushService:
    global _voip_service
    if _voip_service is None:
        _voip_service = VoipPushService()
    return _voip_service
