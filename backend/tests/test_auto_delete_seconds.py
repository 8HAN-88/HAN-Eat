"""Conversation auto-delete TTL setting."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.services.chat_service import ChatService


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[
            User.__table__,
            Conversation.__table__,
            ConversationMember.__table__,
            Message.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@ttl.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _direct(db, a: int, b: int) -> Conversation:
    conv = Conversation(type="direct", created_by_user_id=a)
    db.add(conv)
    db.flush()
    db.add(ConversationMember(conversation_id=conv.id, user_id=a))
    db.add(ConversationMember(conversation_id=conv.id, user_id=b))
    db.flush()
    return conv


def test_set_auto_delete_seconds_direct(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    svc = ChatService(db_session)
    updated = svc.set_auto_delete_seconds(conv.id, 1, 24 * 3600)
    assert int(updated.auto_delete_seconds) == 24 * 3600
    disabled = svc.set_auto_delete_seconds(conv.id, 2, 0)
    assert int(disabled.auto_delete_seconds) == 0


def test_set_auto_delete_caps_at_30_days(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    svc = ChatService(db_session)
    updated = svc.set_auto_delete_seconds(conv.id, 1, 99 * 24 * 3600)
    assert int(updated.auto_delete_seconds) == 30 * 24 * 3600
