"""Unit tests for PushKit VoIP payload / config helpers."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.services.voip_push_service import (
    build_voip_payload,
    voip_push_configured,
)


def test_build_voip_payload_incoming():
    payload = build_voip_payload(
        call_id=42,
        caller_name="Анна",
        media="video",
        conversation_id=7,
        caller_avatar="https://x/a.jpg",
        call_kind="group",
        action="incoming",
    )
    assert payload["aps"]["content-available"] == 1
    assert payload["data"]["call_id"] == "42"
    assert payload["data"]["caller_name"] == "Анна"
    assert payload["data"]["media"] == "video"
    assert payload["data"]["conversation_id"] == "7"
    assert payload["data"]["call_kind"] == "group"
    assert payload["data"]["type"] == "call.incoming"
    assert payload["data"]["action"] == "incoming"
    # Flat mirrors for AppDelegate fallbacks.
    assert payload["call_id"] == "42"


def test_build_voip_payload_end():
    payload = build_voip_payload(
        call_id=9,
        caller_name="x",
        action="end",
    )
    assert payload["data"]["action"] == "end"
    assert payload["data"]["type"] == "call.ended"


def test_voip_not_configured_by_default(monkeypatch):
    from app.core import config as cfg

    monkeypatch.setattr(cfg.settings, "APNS_KEY_ID", "")
    monkeypatch.setattr(cfg.settings, "APNS_TEAM_ID", "")
    monkeypatch.setattr(cfg.settings, "APNS_AUTH_KEY", "")
    monkeypatch.setattr(cfg.settings, "APNS_AUTH_KEY_PATH", "")
    assert voip_push_configured() is False


def test_build_apns_jwt_es256(monkeypatch):
    from cryptography.hazmat.backends import default_backend
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    from app.core import config as cfg
    from app.services import voip_push_service as voip

    key = ec.generate_private_key(ec.SECP256R1(), default_backend())
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    monkeypatch.setattr(cfg.settings, "APNS_KEY_ID", "ABC123XYZ")
    monkeypatch.setattr(cfg.settings, "APNS_TEAM_ID", "TEAM123456")
    monkeypatch.setattr(cfg.settings, "APNS_AUTH_KEY", pem)
    monkeypatch.setattr(cfg.settings, "APNS_AUTH_KEY_PATH", "")
    monkeypatch.setattr(cfg.settings, "APNS_BUNDLE_ID", "com.haneat.app")
    voip._jwt_cache["token"] = None
    voip._jwt_cache["exp"] = 0.0
    assert voip.voip_push_configured() is True
    token = voip.build_apns_jwt(force=True)
    assert isinstance(token, str) and token.count(".") == 2


def test_build_fcm_data_includes_call_kind():
    from app.models.notification import Notification
    from app.services.push_service import PushService

    notification = Notification(
        user_id=1,
        type="call.incoming",
        entity_type="call",
        entity_id=5,
        actor_id=2,
        title="Bob",
        body="Входящий звонок",
        data={
            "call_id": 5,
            "conversation_id": 3,
            "media": "voice",
            "caller_name": "Bob",
            "caller_avatar": "https://x/b.jpg",
            "call_kind": "group",
            "route": "call",
        },
    )
    data = PushService._build_fcm_data(notification)
    assert data["call_id"] == "5"
    assert data["call_kind"] == "group"
    assert data["caller_avatar"] == "https://x/b.jpg"
    assert data["route"] == "call"
