"""Story reply message validation helpers."""
import json
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import Conversation, ConversationMember, Message
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
                email=f"u{uid}@storyreply.test",
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


def test_send_story_reply_ok(db_session):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    content = json.dumps(
        {
            "story_id": 42,
            "author_id": 2,
            "author_name": "U2",
            "media_url": "https://cdn.example/s.jpg",
            "media_type": "image",
            "text": "Круто!",
        },
        ensure_ascii=False,
    )
    msg, is_new = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="story_reply",
        content=content,
    )
    assert is_new is True
    assert msg.type == "story_reply"
    assert "Круто!" in msg.content


@pytest.mark.parametrize(
    "payload,code",
    [
        ({}, "invalid_story_reply"),
        ({"story_id": 1, "author_id": 2, "text": ""}, "empty_story_reply"),
        ({"story_id": 0, "author_id": 2, "text": "hi"}, "invalid_story_reply"),
        ({"story_id": 1, "author_id": 2, "text": "x" * 1001}, "story_reply_too_long"),
    ],
)
def test_send_story_reply_validation(db_session, payload, code):
    conv = _setup_direct(db_session)
    svc = ChatService(db_session)
    with pytest.raises(ValueError, match=code):
        svc.send_message(
            conversation_id=conv.id,
            sender_id=1,
            msg_type="story_reply",
            content=json.dumps(payload),
        )
