"""Tests for 1:1 WebRTC call lifecycle."""
import pytest
from datetime import datetime, timedelta
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.core.database import Base
from app.models.call import CallParticipant, CallSession
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.models.user_block import UserBlock
from app.models.notification import Notification
from app.services.call_service import CallService, ring_timeout_seconds


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
            CallSession.__table__,
            CallParticipant.__table__,
            UserBlock.__table__,
            Notification.__table__,
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
        email=f"u{user_id}@c.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _direct(db, a: int, b: int) -> Conversation:
    low, high = (a, b) if a < b else (b, a)
    conv = Conversation(type="direct", direct_user_low_id=low, direct_user_high_id=high)
    db.add(conv)
    db.flush()
    db.add(ConversationMember(conversation_id=conv.id, user_id=a))
    db.add(ConversationMember(conversation_id=conv.id, user_id=b))
    db.flush()
    return conv


def test_create_answer_end_call(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    db_session.commit()

    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    svc.notify_incoming(call)
    assert call.status == "ringing"
    assert call.caller_id == 1
    assert call.callee_id == 2

    answered = svc.answer_call(2, call.id)
    db_session.commit()
    assert answered.status == "active"
    assert answered.started_at is not None

    ended = svc.end_call(1, call.id)
    db_session.commit()
    assert ended.status == "ended"
    assert ended.ended_by_user_id == 1
    note = (
        db_session.query(Message)
        .filter(Message.conversation_id == conv.id, Message.type == "call")
        .first()
    )
    assert note is not None
    assert '"status": "ended"' in note.content


def test_reject_and_busy(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    conv12 = _direct(db_session, 1, 2)
    conv13 = _direct(db_session, 1, 3)
    db_session.commit()

    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv12.id, media="video")
    db_session.commit()
    rejected = svc.reject_call(2, call.id)
    db_session.commit()
    assert rejected.status == "rejected"
    assert (
        db_session.query(Message)
        .filter(Message.conversation_id == conv12.id, Message.type == "call")
        .count()
        == 1
    )

    active = svc.create_call(1, conversation_id=conv12.id, media="voice")
    db_session.commit()
    svc.answer_call(2, active.id)
    db_session.commit()

    with pytest.raises(HTTPException) as busy:
        svc.create_call(1, conversation_id=conv13.id, media="voice")
    assert busy.value.status_code == 409


def test_signal_relay_requires_participant(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    conv = _direct(db_session, 1, 2)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    svc.answer_call(2, call.id)
    db_session.commit()

    svc.relay_signal(
        1,
        call.id,
        kind="offer",
        payload={"sdp": "v=0", "type": "offer"},
    )
    db_session.commit()

    with pytest.raises(HTTPException) as forbidden:
        svc.relay_signal(
            3,
            call.id,
            kind="ice",
            payload={"candidate": "x"},
        )
    assert forbidden.value.status_code == 403


def test_expire_stale_rings_marks_missed(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _direct(db_session, 1, 2)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    call.created_at = datetime.utcnow() - timedelta(seconds=ring_timeout_seconds() + 5)
    db_session.commit()

    expired = CallService.expire_stale_rings(db_session)
    db_session.commit()
    assert len(expired) == 1
    db_session.refresh(call)
    assert call.status == "missed"
    note = (
        db_session.query(Message)
        .filter(Message.conversation_id == conv.id, Message.type == "call")
        .first()
    )
    assert note is not None
    assert '"status": "missed"' in note.content


def test_ice_servers_include_stun(db_session):
    servers = CallService.ice_servers()
    assert isinstance(servers, list)
    assert any("stun" in str(s.get("urls", "")).lower() for s in servers)
