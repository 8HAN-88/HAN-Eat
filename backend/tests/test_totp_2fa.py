"""TOTP 2FA enroll / login challenge."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pyotp
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.core.security import get_password_hash
from app.models.auth_session import AuthSession
from app.models.user import User
from app.services import totp_service as totp


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[User.__table__, AuthSession.__table__],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, *, enabled=False):
    secret = totp.generate_secret() if enabled else None
    u = User(
        email="twofa@test.local",
        password_hash=get_password_hash("password123"),
        name="TwoFA",
        totp_secret=secret,
        totp_enabled=enabled,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def test_verify_code_accepts_current_totp():
    secret = totp.generate_secret()
    code = pyotp.TOTP(secret).now()
    assert totp.verify_code(secret, code)
    assert not totp.verify_code(secret, "000000")


def test_pending_token_roundtrip():
    token = totp.create_pending_token(99)
    assert totp.decode_pending_token(token) == 99
    assert totp.decode_pending_token("not-a-jwt") is None


def test_is_2fa_enabled_requires_secret_and_flag(db_session):
    u = _user(db_session, enabled=False)
    assert not totp.is_2fa_enabled(u)
    u.totp_secret = totp.generate_secret()
    u.totp_enabled = True
    db_session.commit()
    assert totp.is_2fa_enabled(u)


def test_login_challenge_then_verify(db_session):
    """Mirrors API flow at the service layer used by endpoints."""
    from app.services.auth_session_service import create_session

    user = _user(db_session, enabled=True)
    assert totp.is_2fa_enabled(user)
    pending = totp.create_pending_token(user.id)
    uid = totp.decode_pending_token(pending)
    assert uid == user.id
    code = pyotp.TOTP(user.totp_secret).now()
    assert totp.verify_code(user.totp_secret, code)
    access, refresh, session = create_session(db_session, user=user)
    db_session.commit()
    assert access and refresh and session.id
