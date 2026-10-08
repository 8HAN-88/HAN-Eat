"""New-password rules (bcrypt length + trivial rejects)."""
import pytest
from pydantic import ValidationError

from app.core.security import get_password_hash, validate_new_password, verify_password
from app.schemas.auth import ChangePasswordRequest, RegisterRequest, ResetPasswordRequest


def test_validate_new_password_accepts_normal():
    assert validate_new_password("correct-horse-1") == "correct-horse-1"


def test_validate_new_password_rejects_short_and_trivial():
    with pytest.raises(ValueError):
        validate_new_password("short")
    with pytest.raises(ValueError):
        validate_new_password("password123")
    with pytest.raises(ValueError):
        validate_new_password("  padded12")
    with pytest.raises(ValueError):
        validate_new_password("a" * 80)


def test_hash_roundtrip():
    hashed = get_password_hash("correct-horse-1")
    assert verify_password("correct-horse-1", hashed) is True
    assert verify_password("wrong-pass-1", hashed) is False


def test_register_schema_rejects_trivial_password():
    with pytest.raises(ValidationError):
        RegisterRequest(
            email="a@b.co",
            password="password123",
            name="Ann",
            accept_legal=True,
        )
    ok = RegisterRequest(
        email="a@b.co",
        password="correct-horse-1",
        name="Ann",
        accept_legal=True,
    )
    assert ok.password == "correct-horse-1"


def test_reset_and_change_use_same_rule():
    with pytest.raises(ValidationError):
        ResetPasswordRequest(token="123456", new_password="12345678")
    with pytest.raises(ValidationError):
        ChangePasswordRequest(current_password="old", new_password="qwerty123")
