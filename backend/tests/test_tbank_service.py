"""Unit tests for T-Bank payment service (token, order id, notifications)."""
from __future__ import annotations

import hashlib

import pytest

from app.services.tbank_service import TBankService


@pytest.fixture
def tbank(monkeypatch):
    monkeypatch.setattr(
        "app.services.tbank_service.settings.TBANK_ENABLED",
        True,
        raising=False,
    )
    monkeypatch.setattr(
        "app.services.tbank_service.settings.TBANK_TERMINAL_KEY",
        "TestTerminal",
        raising=False,
    )
    monkeypatch.setattr(
        "app.services.tbank_service.settings.TBANK_PASSWORD",
        "test_password",
        raising=False,
    )
    monkeypatch.setattr(
        "app.services.tbank_service.settings.API_PUBLIC_BASE_URL",
        "https://api.example.com",
        raising=False,
    )
    return TBankService()


def test_make_and_parse_order_id():
    oid = TBankService.make_order_id(42)
    assert oid.startswith("HE42-")
    assert TBankService.parse_user_id_from_order_id(oid) == 42
    assert TBankService.parse_user_id_from_order_id("invalid") is None


def test_notification_token(tbank):
    payload = {
        "TerminalKey": "TestTerminal",
        "OrderId": "HE1-abc123def456",
        "Success": True,
        "Status": "CONFIRMED",
        "PaymentId": 12345,
        "Amount": 64900,
    }
    token_params = {
        "Amount": 64900,
        "OrderId": "HE1-abc123def456",
        "Password": "test_password",
        "PaymentId": 12345,
        "Status": "CONFIRMED",
        "Success": True,
        "TerminalKey": "TestTerminal",
    }
    concat = "".join(str(token_params[k]) for k in sorted(token_params.keys()))
    payload["Token"] = hashlib.sha256(concat.encode("utf-8")).hexdigest()
    assert tbank.verify_notification_token(payload) is True

    parsed = tbank.parse_notification(payload)
    assert parsed["paid"] is True
    assert parsed["payment_id"] == "12345"
    assert parsed["user_id"] == 1


def test_sbp_recurring_flag(monkeypatch):
    monkeypatch.setattr(
        "app.services.tbank_service.settings.TBANK_ENABLED",
        True,
        raising=False,
    )
    monkeypatch.setattr(
        "app.services.tbank_service.settings.TBANK_SBP_RECURRING_ENABLED",
        True,
        raising=False,
    )
    assert TBankService.sbp_recurring_enabled() is True
