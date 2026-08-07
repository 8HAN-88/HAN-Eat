"""Clear history: self-only vs also for DM peer."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from datetime import datetime, timezone

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
        email=f"u{user_id}@clear.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _direct(db, a: int, b: int) -> Conversation:
    low, high = (a, b) if a < b else (b, a)
    conv = Conversation(
        type="direct",
        created_by_user_id=a,
        direct_user_low_id=low,
        direct_user_high_id=high,
    )
    db.add(conv)
    db.flush()
    db.add(ConversationMember(conversation_id=conv.id, user_id=a))
    db.add(ConversationMember(conversation_id=conv.id, user_id=b))
    db.flush()
    return conv


def _group(db, creator_id: int, *member_ids: int) -> Conversation:
    conv = Conversation(
        type="group", title="G", created_by_user_id=creator_id
    )
    db.add(conv)
    db.flush()
    for uid in (creator_id,) + member_ids:
        db.add(
            ConversationMember(
                conversation_id=conv.id,
                user_id=uid,
                is_admin=uid == creator_id,
            )
        )
    db.flush()
    return conv


def _msg(db, conv_id: int, sender_id: int, text: str = "hi") -> Message:
    m = Message(
        conversation_id=conv_id,
        sender_id=sender_id,
        type="text",
        content=text,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    db.add(m)
    db.flush()
    return m


def test_clear_history_self_only(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    msg = _msg(db_session, conv.id, 1)
    svc = ChatService(db_session)
    cleared_to, peer = svc.clear_history(conv.id, 1, also_for_peer=False)
    assert cleared_to == msg.id
    assert peer is None
    m1 = (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=conv.id, user_id=1)
        .one()
    )
    m2 = (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=conv.id, user_id=2)
        .one()
    )
    assert m1.history_cleared_before_id == msg.id
    assert m2.history_cleared_before_id is None


def test_clear_history_also_for_peer(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    msg = _msg(db_session, conv.id, 1)
    svc = ChatService(db_session)
    cleared_to, peer = svc.clear_history(conv.id, 1, also_for_peer=True)
    assert cleared_to == msg.id
    assert peer == 2
    m1 = (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=conv.id, user_id=1)
        .one()
    )
    m2 = (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=conv.id, user_id=2)
        .one()
    )
    assert m1.history_cleared_before_id == msg.id
    assert m2.history_cleared_before_id == msg.id


def test_clear_history_also_for_peer_rejects_group(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    _msg(db_session, conv.id, 1)
    svc = ChatService(db_session)
    with pytest.raises(ValueError, match="also_for_peer_direct_only"):
        svc.clear_history(conv.id, 1, also_for_peer=True)
