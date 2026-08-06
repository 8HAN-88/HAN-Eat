"""Media spoiler flag on send / schedule."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message, ScheduledMessage
from app.models.user import User
from app.models.user_block import UserBlock
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
            ScheduledMessage.__table__,
            UserBlock.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _setup_direct(db):
    for uid in (1, 2):
        db.add(
            User(
                id=uid,
                email=f"u{uid}@spoiler.test",
                password_hash="h",
                name=f"U{uid}",
            )
        )
    conv = Conversation(
        type="direct",
        direct_user_low_id=1,
        direct_user_high_id=2,
    )
    db.add(conv)
    db.flush()
    for uid in (1, 2):
        db.add(ConversationMember(conversation_id=conv.id, user_id=uid))
    db.commit()
    return conv


def test_send_image_with_spoiler(db_session):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    msg, is_new = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="image",
        content="cap",
        media_url="https://cdn.example/a.jpg",
        has_spoiler=True,
    )
    assert is_new is True
    assert msg.has_spoiler is True


def test_spoiler_ignored_for_text(db_session):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    msg, _ = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="hello",
        has_spoiler=True,
    )
    assert msg.has_spoiler is False


def test_schedule_image_keeps_spoiler(db_session):
    from datetime import datetime, timedelta, timezone

    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    send_at = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=1)
    item = svc.schedule_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="image",
        content="",
        media_url="https://cdn.example/b.jpg",
        send_at=send_at,
        has_spoiler=True,
    )
    assert item.has_spoiler is True
