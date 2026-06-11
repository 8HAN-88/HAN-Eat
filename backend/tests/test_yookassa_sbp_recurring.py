"""Тесты СБП-рекуррента через ЮKassa API."""
from unittest.mock import MagicMock, patch

import pytest

from app.services.yookassa_service import YooKassaService


class _FakeConfirmation:
    confirmation_url = "https://yookassa.ru/confirm"


class _FakePayment:
    id = "pay-test-1"
    status = "pending"
    confirmation = _FakeConfirmation()
    paid = False


@pytest.fixture
def yk_enabled(monkeypatch):
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_ENABLED", True
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_SHOP_ID", "shop"
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_SECRET_KEY", "secret"
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_PAYMENT_METHOD", "sbp"
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_SBP_RECURRING_ENABLED",
        True,
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.YOOKASSA_AVAILABLE", True
    )
    svc = YooKassaService()
    svc.enabled = True
    return svc


def test_create_payment_sbp_skips_save_when_recurring_disabled(monkeypatch):
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_ENABLED", True
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_SBP_RECURRING_ENABLED",
        False,
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.settings.YOOKASSA_PAYMENT_METHOD", "sbp"
    )
    monkeypatch.setattr(
        "app.services.yookassa_service.YOOKASSA_AVAILABLE", True
    )
    svc = YooKassaService()
    svc.enabled = True
    captured = {}

    def fake_create(payload, key):
        captured["payload"] = payload
        return _FakePayment()

    with patch(
        "app.services.yookassa_service.Payment.create", side_effect=fake_create
    ):
        svc.create_payment(
            user_id=1,
            user_email="u@test.ru",
            amount=499.0,
            plan="monthly",
            product="pro",
        )

    assert "save_payment_method" not in captured["payload"]


def test_create_payment_sbp_saves_payment_method(yk_enabled):
    captured = {}

    def fake_create(payload, key):
        captured["payload"] = payload
        captured["key"] = key
        return _FakePayment()

    with patch(
        "app.services.yookassa_service.Payment.create", side_effect=fake_create
    ):
        yk_enabled.create_payment(
            user_id=1,
            user_email="u@test.ru",
            amount=499.0,
            plan="monthly",
            product="pro",
        )

    assert captured["payload"]["save_payment_method"] is True
    assert captured["payload"]["payment_method_data"] == {"type": "sbp"}


def test_create_autopayment_uses_payment_method_id(yk_enabled):
    captured = {}

    def fake_create(payload, key):
        captured["payload"] = payload
        return MagicMock(id="pay-renew-1", status="pending", paid=False)

    with patch(
        "app.services.yookassa_service.Payment.create", side_effect=fake_create
    ):
        yk_enabled.create_autopayment(
            user_id=1,
            user_email="u@test.ru",
            amount=499.0,
            plan="monthly",
            product="pro",
            payment_method_id="pm-abc",
            metadata_extra={"renewal": "1", "subscription_id": "5"},
        )

    assert captured["payload"]["payment_method_id"] == "pm-abc"
    assert "confirmation" not in captured["payload"]
    assert captured["payload"]["metadata"]["renewal"] == "1"
