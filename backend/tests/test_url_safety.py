"""Public-host checks for webhooks, previews, and OAuth return URLs."""
import pytest
from fastapi import HTTPException

from app.core.url_safety import (
    is_private_or_local_host,
    profile_media_url_allowed,
    require_public_http_url,
)
from app.services.yandex_oauth_service import redirect_uri_allowed
from app.schemas.user import UserResponse
from datetime import datetime


def test_private_hosts_are_blocked():
    assert is_private_or_local_host("127.0.0.1") is True
    assert is_private_or_local_host("localhost") is True
    assert is_private_or_local_host("10.0.0.8") is True
    assert is_private_or_local_host("192.168.1.5") is True
    assert is_private_or_local_host("169.254.169.254") is True
    assert is_private_or_local_host("metadata.google.internal") is True
    assert is_private_or_local_host("example.com") is False


def test_profile_media_url_rejects_script_and_loopback():
    with pytest.raises(ValueError):
        profile_media_url_allowed("javascript:alert(1)")
    with pytest.raises(ValueError):
        profile_media_url_allowed("http://127.0.0.1/x.png")
    with pytest.raises(ValueError):
        profile_media_url_allowed("uploads/../secret")
    assert profile_media_url_allowed("") == ""
    assert profile_media_url_allowed("uploads/u/1.jpg") == "uploads/u/1.jpg"
    assert profile_media_url_allowed("/uploads/u/1.jpg") == "/uploads/u/1.jpg"
    assert (
        profile_media_url_allowed("https://cdn.haneat.app/a.jpg")
        == "https://cdn.haneat.app/a.jpg"
    )


def test_require_public_http_url_rejects_loopback():
    with pytest.raises(ValueError):
        require_public_http_url("http://127.0.0.1:5001/admin")
    with pytest.raises(ValueError):
        require_public_http_url("https://localhost/hook")


def test_bot_webhook_rejects_private_url():
    from app.api.v1.bots import _validate_webhook_url

    with pytest.raises(HTTPException) as exc:
        _validate_webhook_url("http://127.0.0.1/hook")
    assert exc.value.status_code == 400


def test_yandex_redirect_only_own_hosts():
    assert redirect_uri_allowed("https://haneat.app/auth/yandex") is True
    assert redirect_uri_allowed("http://localhost:8080/auth/yandex") is True
    assert redirect_uri_allowed("https://evil.example/steal") is False


def test_profile_public_view_hides_mailbox_and_admin():
    raw = UserResponse(
        id=3,
        email="secret@example.com",
        name="Ann",
        is_private=False,
        created_at=datetime(2026, 1, 1),
        is_admin=True,
        is_moderator=True,
        trust_score=0.1,
        totp_enabled=True,
        email_verified=True,
        phone="7999",
    )
    pub = raw.public_view()
    assert pub.email == ""
    assert pub.phone is None
    assert pub.is_admin is False
    assert pub.is_moderator is False
    assert pub.trust_score is None
    assert pub.totp_enabled is False
    assert pub.name == "Ann"
    assert raw.email == "secret@example.com"
