"""Security-focused tests for mini apps policy."""

import pytest
from fastapi import HTTPException

from app.api.v1 import miniapps as m


def test_ensure_url_rejects_private_local_hosts(monkeypatch):
    monkeypatch.setattr(m.settings, "MINIAPP_BLOCK_PRIVATE_HOSTS", True)
    monkeypatch.setattr(m.settings, "MINIAPP_ALLOWED_HOSTS", [])
    monkeypatch.setattr(m.settings, "APP_ENV", "production")

    with pytest.raises(HTTPException) as exc:
        m._ensure_url("https://127.0.0.1/app")
    assert exc.value.status_code == 400
    assert "Local/private hosts" in str(exc.value.detail)


def test_ensure_url_allows_subdomain_for_allowed_hosts(monkeypatch):
    monkeypatch.setattr(m.settings, "MINIAPP_BLOCK_PRIVATE_HOSTS", True)
    monkeypatch.setattr(m.settings, "MINIAPP_ALLOWED_HOSTS", ["example.com"])

    assert m._ensure_url("https://mini.example.com/app") == "https://mini.example.com/app"


def test_host_allowed_exact_and_subdomain():
    allowed = {"example.com"}
    assert m._host_allowed("example.com", allowed) is True
    assert m._host_allowed("x.example.com", allowed) is True
    assert m._host_allowed("evil-example.com", allowed) is False


def test_ensure_url_rejects_credentials_and_fragment(monkeypatch):
    monkeypatch.setattr(m.settings, "MINIAPP_BLOCK_PRIVATE_HOSTS", True)
    monkeypatch.setattr(m.settings, "MINIAPP_ALLOWED_HOSTS", [])
    monkeypatch.setattr(m.settings, "APP_ENV", "production")

    with pytest.raises(HTTPException) as exc1:
        m._ensure_url("https://user:pass@example.com/app")
    assert "credentials" in str(exc1.value.detail).lower()

    with pytest.raises(HTTPException) as exc2:
        m._ensure_url("https://example.com/app#token")
    assert "fragments" in str(exc2.value.detail).lower()


def test_url_risk_summary_marks_non_https_as_medium():
    summary = m._url_risk_summary("http://example.com/app?x=1")
    assert summary["host"] == "example.com"
    assert summary["scheme"] == "http"
    assert summary["risk_level"] == "medium"
    assert "non_https" in summary["risk_reasons"]


def test_inline_keyboard_accepts_web_app_miniapp_id():
    from app.api.v1.chats import _normalize_inline_keyboard
    from app.api.v1.bots import BotInlineButton, _normalize_inline_buttons

    normalized = _normalize_inline_keyboard(
        [[{"text": "Open", "web_app": {"miniapp_id": 42}}]]
    )
    assert normalized == [
        [{"text": "Open", "miniapp_id": 42, "web_app": {"miniapp_id": 42}}]
    ]

    from_bot = _normalize_inline_buttons(
        [BotInlineButton(text="Play", miniapp_id=7)]
    )
    assert from_bot == [
        [{"text": "Play", "miniapp_id": 7, "web_app": {"miniapp_id": 7}}]
    ]


def test_bot_handler_keeps_web_app_buttons():
    from app.services.bot_handler import _normalize_inline_buttons

    rows = _normalize_inline_buttons(
        [[{"text": "App", "miniapp_id": 9, "callback_data": "ignored_ok"}]]
    )
    assert rows[0][0]["miniapp_id"] == 9
    assert rows[0][0]["web_app"]["miniapp_id"] == 9
