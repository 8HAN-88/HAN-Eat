"""Last-seen privacy tiers."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Contact
from app.models.user import User
from app.services.last_seen_privacy import (
    PRIVACY_CONTACTS,
    PRIVACY_EVERYBODY,
    PRIVACY_NOBODY,
    apply_last_seen_privacy_update,
    can_viewer_see_last_seen,
    resolve_last_seen_privacy,
)


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[User.__table__, Contact.__table__],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, uid: int, privacy: str = PRIVACY_EVERYBODY):
    u = User(
        id=uid,
        email=f"u{uid}@test.com",
        name=f"U{uid}",
        password_hash="x",
        show_last_seen=privacy != PRIVACY_NOBODY,
        last_seen_privacy=privacy,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def test_resolve_falls_back_to_show_last_seen(db_session):
    u = User(
        id=1,
        email="a@test.com",
        name="A",
        password_hash="x",
        show_last_seen=False,
    )
    # Column may be defaulted by model; force missing-like via nobody sync path.
    apply_last_seen_privacy_update(u, show_last_seen=False)
    assert resolve_last_seen_privacy(u) == PRIVACY_NOBODY
    apply_last_seen_privacy_update(u, show_last_seen=True)
    assert resolve_last_seen_privacy(u) == PRIVACY_EVERYBODY
    assert u.show_last_seen is True


def test_contacts_tier_requires_contact_row(db_session):
    owner = _user(db_session, 1, PRIVACY_CONTACTS)
    viewer = _user(db_session, 2)
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is False
    db_session.add(Contact(owner_user_id=owner.id, contact_user_id=viewer.id))
    db_session.commit()
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is True


def test_nobody_hides_from_others_not_self(db_session):
    owner = _user(db_session, 1, PRIVACY_NOBODY)
    assert can_viewer_see_last_seen(db_session, owner, 2) is False
    assert can_viewer_see_last_seen(db_session, owner, 1) is True


def test_hiding_viewer_cannot_see_others(db_session):
    owner = _user(db_session, 1, PRIVACY_EVERYBODY)
    viewer = _user(db_session, 2, PRIVACY_NOBODY)
    assert can_viewer_see_last_seen(db_session, owner, viewer.id) is False
    assert can_viewer_see_last_seen(db_session, owner, owner.id) is True


def test_apply_explicit_privacy_syncs_bool(db_session):
    u = _user(db_session, 1)
    apply_last_seen_privacy_update(u, last_seen_privacy=PRIVACY_CONTACTS)
    assert u.last_seen_privacy == PRIVACY_CONTACTS
    assert u.show_last_seen is True
    apply_last_seen_privacy_update(u, last_seen_privacy=PRIVACY_NOBODY)
    assert u.show_last_seen is False
