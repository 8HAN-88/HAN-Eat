"""Pin message notify respects mute / notify_mode."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import (
    Conversation,
    ConversationMember,
    ConversationPinnedMessage,
    Message,
)
from app.models.notification import Notification
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
            ConversationPinnedMessage.__table__,
            Message.__table__,
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
        email=f"u{user_id}@pin.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _group(db, creator_id: int, *member_ids: int) -> Conversation:
    conv = Conversation(
        type="group", title="Pins", created_by_user_id=creator_id
    )
    db.add(conv)
    db.flush()
    for uid in (creator_id,) + member_ids:
        is_creator = uid == creator_id
        db.add(
            ConversationMember(
                conversation_id=conv.id,
                user_id=uid,
                is_admin=is_creator,
                can_pin_messages=is_creator,
            )
        )
    db.flush()
    return conv


def test_notify_pinned_message_skips_muted_and_actor(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    conv = _group(db_session, 1, 2, 3)
    msg = Message(
        conversation_id=conv.id,
        sender_id=1,
        type="text",
        content="important",
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    db_session.add(msg)
    muted = (
        db_session.query(ConversationMember)
        .filter_by(conversation_id=conv.id, user_id=3)
        .one()
    )
    muted.muted_at = datetime.now(timezone.utc).replace(tzinfo=None)
    muted.notify_mode = "none"
    db_session.flush()

    svc = ChatService(db_session)
    sent = svc.notify_pinned_message(
        conversation_id=conv.id,
        actor_id=1,
        message_id=msg.id,
    )
    assert sent == 1
    rows = db_session.query(Notification).all()
    assert len(rows) == 1
    assert rows[0].user_id == 2
    assert rows[0].data.get("action") == "pin"
    assert "📌" in (rows[0].body or "")
