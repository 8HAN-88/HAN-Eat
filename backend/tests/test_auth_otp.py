"""6-digit email OTP: issue, consume, lockout, legacy tokens."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.core.security import get_password_hash
from app.models.auth_token import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
    AuthToken,
)
from app.models.user import User
from app.services import auth_email_service as mail


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[User.__table__, AuthToken.__table__],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, email="otp@test.local"):
    u = User(
        email=email,
        password_hash=get_password_hash("password123"),
        name="Otp",
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def test_otp_is_six_digits(db_session):
    user = _user(db_session)
    code = mail.create_auth_otp(db_session, user.id, PURPOSE_VERIFY_EMAIL)
    assert mail.is_otp_code(code)
    assert len(code) == 6
    assert code.isdigit()


def test_consume_otp_needs_email(db_session):
    user = _user(db_session)
    code = mail.create_auth_otp(db_session, user.id, PURPOSE_VERIFY_EMAIL)
    row, err = mail.consume_token(db_session, code, PURPOSE_VERIFY_EMAIL)
    assert row is None
    assert err == mail.ERR_NEED_EMAIL


def test_consume_otp_roundtrip(db_session):
    user = _user(db_session)
    code = mail.create_auth_otp(db_session, user.id, PURPOSE_VERIFY_EMAIL)
    row, err = mail.consume_token(
        db_session, f"{code[:3]} {code[3:]}", PURPOSE_VERIFY_EMAIL, email=user.email
    )
    assert err is None
    assert row is not None
    assert row.user_id == user.id
    again, err2 = mail.consume_token(
        db_session, code, PURPOSE_VERIFY_EMAIL, email=user.email
    )
    assert again is None
    assert err2 == mail.ERR_INVALID


def test_wrong_otp_then_lock(db_session):
    user = _user(db_session)
    mail.create_auth_otp(db_session, user.id, PURPOSE_RESET_PASSWORD)
    last_err = None
    for _ in range(5):
        _, last_err = mail.consume_token(
            db_session, "000000", PURPOSE_RESET_PASSWORD, email=user.email
        )
    assert last_err == mail.ERR_LOCKED


def test_legacy_long_token_still_works(db_session):
    user = _user(db_session)
    raw = mail.create_legacy_auth_token(
        db_session, user.id, PURPOSE_VERIFY_EMAIL, hours_valid=2
    )
    assert len(raw) >= 16
    row, err = mail.consume_token(db_session, raw, PURPOSE_VERIFY_EMAIL)
    assert err is None
    assert row is not None


def test_normalize_keeps_legacy_hyphens():
    raw = "abcde-fghij-klmno-pqrstu"
    assert mail.normalize_auth_code(raw) == raw
    assert mail.normalize_auth_code("123 456") == "123456"
    assert mail.normalize_auth_code("12-34-56") == "123456"


def test_legacy_hyphen_token_is_not_stripped(db_session):
    from datetime import datetime, timedelta

    user = _user(db_session)
    raw = "abcde-fghij-klmno-pqrstu"
    row = AuthToken(
        user_id=user.id,
        purpose=PURPOSE_VERIFY_EMAIL,
        token_hash=mail._hash_token(raw),
        expires_at=datetime.utcnow() + timedelta(hours=2),
        created_at=datetime.utcnow(),
    )
    db_session.add(row)
    db_session.flush()
    got, err = mail.consume_token(db_session, raw, PURPOSE_VERIFY_EMAIL)
    assert err is None
    assert got is not None


def test_change_email_otp_resolves_new_address(db_session):
    user = _user(db_session)
    code = mail.create_auth_otp(
        db_session,
        user.id,
        PURPOSE_CHANGE_EMAIL,
        extra_data={"new_email": "new@test.local"},
    )
    row, err = mail.consume_token(
        db_session,
        code,
        PURPOSE_CHANGE_EMAIL,
        email="new@test.local",
    )
    assert err is None
    assert row is not None
    extra = mail._parse_extra(row.extra_data)
    assert extra["new_email"] == "new@test.local"


def test_email_template_shows_grouped_code():
    from app.services.email_templates import render_branded_email

    text, html = render_branded_email(
        preheader="pre",
        title="title",
        greeting=None,
        paragraphs=["body"],
        cta_label="Open",
        cta_url="https://haneat.app",
        otp_code="123456",
    )
    assert "123 456" in html
    assert "Код подтверждения: 123456" in text


def test_same_otp_digits_do_not_collide_across_users(db_session):
    a = _user(db_session, "a@test.local")
    b = _user(db_session, "b@test.local")
    code_a = mail.create_auth_otp(db_session, a.id, PURPOSE_VERIFY_EMAIL)
    code_b = mail.create_auth_otp(db_session, b.id, PURPOSE_VERIFY_EMAIL)
    row_b, err_b = mail.consume_token(
        db_session, code_a, PURPOSE_VERIFY_EMAIL, email=b.email
    )
    if code_a != code_b:
        assert row_b is None
        assert err_b == mail.ERR_INVALID
    row_a, err_a = mail.consume_token(
        db_session, code_a, PURPOSE_VERIFY_EMAIL, email=a.email
    )
    assert err_a is None
    assert row_a is not None
