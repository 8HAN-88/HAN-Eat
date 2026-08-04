"""Tests for small-group WebRTC calls."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.call import CallParticipant, CallSession
from app.models.conversation import Conversation, ConversationMember, Message
from app.models.user import User
from app.models.user_block import UserBlock
from app.models.notification import Notification
from app.services.call_service import CallService, MAX_GROUP_CALL_PARTICIPANTS


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
        email=f"u{user_id}@g.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _group(db, *uids: int) -> Conversation:
    conv = Conversation(type="group", title="G")
    db.add(conv)
    db.flush()
    for uid in uids:
        db.add(ConversationMember(conversation_id=conv.id, user_id=uid))
    db.flush()
    return conv


def test_create_group_call_and_join(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    conv = _group(db_session, 1, 2, 3)
    db_session.commit()

    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    assert call.kind == "group"
    assert call.status == "active"
    assert call.callee_id is None

    parts = (
        db_session.query(CallParticipant)
        .filter(CallParticipant.call_id == call.id)
        .all()
    )
    assert len(parts) <= MAX_GROUP_CALL_PARTICIPANTS
    host = next(p for p in parts if p.user_id == 1)
    assert host.status == "joined"

    joined = svc.answer_call(2, call.id)
    db_session.commit()
    assert joined.status == "active"
    p2 = (
        db_session.query(CallParticipant)
        .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == 2)
        .one()
    )
    assert p2.status == "joined"

    listed = svc.list_participants(1, call.id)
    assert any(x["user_id"] == 2 and x["status"] == "joined" for x in listed)

    ended = svc.end_call(1, call.id)
    db_session.commit()
    assert ended.status == "ended"
    note = (
        db_session.query(Message)
        .filter(Message.conversation_id == conv.id, Message.type == "call")
        .first()
    )
    assert note is not None
    assert '"kind": "group"' in note.content


def test_expire_stale_group_invites(db_session):
    from datetime import datetime, timedelta

    from app.services.call_service import ring_timeout_seconds

    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    call.created_at = datetime.utcnow() - timedelta(seconds=ring_timeout_seconds() + 5)
    db_session.commit()

    CallService.expire_stale_rings(db_session)
    db_session.commit()

    part = (
        db_session.query(CallParticipant)
        .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == 2)
        .one()
    )
    assert part.status == "missed"
    db_session.refresh(call)
    assert call.status == "active"


def test_invite_additional_group_member(db_session):
    from fastapi import HTTPException

    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    _user(db_session, 4)
    _user(db_session, 5)
    # 5 members: create invites first 3 others (max 4 total with host).
    conv = _group(db_session, 1, 2, 3, 4, 5)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()

    parts = (
        db_session.query(CallParticipant)
        .filter(CallParticipant.call_id == call.id)
        .all()
    )
    assert len(parts) == MAX_GROUP_CALL_PARTICIPANTS
    invited_ids = {p.user_id for p in parts}
    assert 1 in invited_ids
    left_out = next(uid for uid in (2, 3, 4, 5) if uid not in invited_ids)

    # Free a seat: one invitee rejects.
    reject_id = next(uid for uid in invited_ids if uid != 1)
    svc.reject_call(reject_id, call.id)
    db_session.commit()

    invited = svc.invite_to_group_call(1, call.id, left_out)
    db_session.commit()
    assert invited.kind == "group"
    row = (
        db_session.query(CallParticipant)
        .filter(CallParticipant.call_id == call.id, CallParticipant.user_id == left_out)
        .one()
    )
    assert row.status == "ringing"

    # Full again — cannot invite another free member.
    live = {
        p.user_id
        for p in db_session.query(CallParticipant)
        .filter(
            CallParticipant.call_id == call.id,
            CallParticipant.status.in_(("joined", "ringing")),
        )
        .all()
    }
    candidate = next(uid for uid in (2, 3, 4, 5) if uid not in live)
    with pytest.raises(HTTPException) as full:
        svc.invite_to_group_call(1, call.id, candidate)
    assert full.value.status_code == 409


def test_group_mute_broadcast_without_to_user(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    conv = _group(db_session, 1, 2, 3)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="voice")
    db_session.commit()
    svc.answer_call(2, call.id)
    db_session.commit()
    svc.answer_call(3, call.id)
    db_session.commit()

    # Control signals may omit to_user_id and fan out to joined peers.
    svc.relay_signal(
        1,
        call.id,
        kind="mute",
        payload={"muted": True},
    )
    db_session.commit()


def test_group_signal_requires_to_user(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    db_session.commit()
    svc = CallService(db_session)
    call = svc.create_call(1, conversation_id=conv.id, media="video")
    db_session.commit()
    svc.answer_call(2, call.id)
    db_session.commit()

    with pytest.raises(Exception) as exc:
        svc.relay_signal(1, call.id, kind="offer", payload={"sdp": "x"})
    assert exc.value.status_code == 400

    svc.relay_signal(
        1,
        call.id,
        kind="offer",
        payload={"sdp": "x", "type": "offer"},
        to_user_id=2,
    )
    db_session.commit()
