"""Тесты юридического согласия."""
from datetime import datetime

from app.models.user import User
from app.services.legal_consent_service import (
    consent_required,
    current_legal_version,
    record_consent,
)


def test_consent_required_without_timestamp():
    user = User(
        id=1,
        email="a@test.ru",
        password_hash="x",
        name="Test",
    )
    assert consent_required(user) is True


def test_consent_required_wrong_version():
    user = User(
        id=1,
        email="a@test.ru",
        password_hash="x",
        name="Test",
        legal_consent_version="2020-01-01",
        legal_consent_at=datetime.utcnow(),
    )
    assert consent_required(user) is True


def test_record_consent_sets_current_version():
    user = User(
        id=1,
        email="b@test.ru",
        password_hash="x",
        name="Test",
    )

    class _FakeDb:
        def add(self, _obj):
            pass

        def flush(self):
            pass

    record_consent(user, _FakeDb())
    assert user.legal_consent_version == current_legal_version()
    assert user.legal_consent_at is not None
    assert consent_required(user) is False
