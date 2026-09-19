"""Auth sessions create / revoke."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.core.security import decode_token
from app.models.auth_session import AuthSession
from app.models.user import User
from app.services import auth_session_service as svc


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


def _user(db, uid=1):
    u = User(
        id=uid,
        email=f"u{uid}@sess.test",
        password_hash="h",
        name=f"U{uid}",
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def test_create_session_puts_sid_in_refresh(db_session):
    user = _user(db_session)
    access, refresh, session = svc.create_session(
        db_session,
        user=user,
        device_name="HanWe web",
        device_platform="web",
    )
    db_session.commit()
    assert access
    payload = decode_token(refresh)
    assert payload is not None
    assert payload["type"] == "refresh"
    assert int(payload["sid"]) == session.id
    assert payload["jti"] == session.jti


def test_revoke_other_keeps_current(db_session):
    user = _user(db_session)
    _, _, a = svc.create_session(db_session, user=user, device_name="A")
    _, _, b = svc.create_session(db_session, user=user, device_name="B")
    db_session.commit()
    count = svc.revoke_other_sessions(
        db_session, user_id=user.id, keep_session_id=a.id
    )
    db_session.commit()
    assert count == 1
    active = svc.list_sessions(db_session, user_id=user.id)
    assert len(active) == 1
    assert active[0].id == a.id
    assert svc.get_active_session(db_session, session_id=b.id, jti=b.jti) is None


def test_create_session_fills_label_from_user_agent(db_session):
    user = _user(db_session)
    _, _, session = svc.create_session(
        db_session,
        user=user,
        user_agent=(
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        ),
    )
    db_session.commit()
    assert session.device_name == "Chrome · Linux"
    assert session.device_platform == "web"


def test_session_display_name_prefers_explicit_device():
    from app.services.session_device_label import display_device_name

    assert (
        display_device_name(
            device_name="HanWe browser",
            device_platform="web",
            user_agent="Mozilla/5.0 Chrome/128",
        )
        == "HanWe browser"
    )
    assert (
        display_device_name(
            device_name=None,
            device_platform=None,
            user_agent=(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
                "Mobile/15E148 Safari/604.1"
            ),
        )
        == "Safari · iPhone"
    )
    assert (
        display_device_name(
            device_name=None,
            device_platform="web",
            user_agent=None,
        )
        == "Браузер"
    )


def test_rotate_updates_jti(db_session):
    user = _user(db_session)
    _, refresh1, session = svc.create_session(db_session, user=user)
    db_session.commit()
    old_jti = session.jti
    _, refresh2 = svc.rotate_session_tokens(db_session, session=session, user=user)
    db_session.commit()
    assert session.jti != old_jti
    payload = decode_token(refresh2)
    assert payload["jti"] == session.jti
    assert svc.get_active_session(
        db_session, session_id=session.id, jti=old_jti
    ) is None
