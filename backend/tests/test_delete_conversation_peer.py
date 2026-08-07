"""Delete conversation: self-only vs also for DM peer."""
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
        email=f"u{user_id}@del.test",
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


def test_delete_conversation_self_only_keeps_peer(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    cid = conv.id
    svc = ChatService(db_session)
    peer = svc.delete_conversation(cid, 1, also_for_peer=False)
    assert peer is None
    assert (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=cid, user_id=1)
        .first()
        is None
    )
    assert (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=cid, user_id=2)
        .first()
        is not None
    )
    assert db_session.query(Conversation).filter_by(id=cid).first() is not None


def test_delete_conversation_also_for_peer(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    cid = conv.id
    svc = ChatService(db_session)
    peer = svc.delete_conversation(cid, 1, also_for_peer=True)
    assert peer == 2
    assert (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=cid)
        .count()
        == 0
    )
    assert db_session.query(Conversation).filter_by(id=cid).first() is None


def test_delete_conversation_also_for_peer_rejects_group(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    with pytest.raises(ValueError, match="also_for_peer_direct_only"):
        svc.delete_conversation(conv.id, 1, also_for_peer=True)
