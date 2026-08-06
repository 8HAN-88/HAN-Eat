"""Scheduled messages keep effect_id and topic_id through dispatch."""
import os
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base
from app.models.conversation import (
    Conversation,
    ConversationMember,
    Message,
    MessageHide,
    ScheduledMessage,
)
from app.models.forum_topic import ForumTopic
from app.models.notification import Notification
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
            MessageHide.__table__,
            ScheduledMessage.__table__,
            ForumTopic.__table__,
            Notification.__table__,
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


def _users(db, *ids):
    for uid in ids:
        db.add(
            User(
                id=uid,
                email=f"u{uid}@sched.test",
                password_hash="h",
                name=f"U{uid}",
            )
        )
    db.flush()


def _direct(db, a: int, b: int) -> Conversation:
    low, high = (a, b) if a < b else (b, a)
    conv = Conversation(
        type="direct", direct_user_low_id=low, direct_user_high_id=high
    )
    db.add(conv)
    db.flush()
    for uid in (a, b):
        db.add(ConversationMember(conversation_id=conv.id, user_id=uid))
    db.flush()
    return conv


def _group(db, creator_id: int, *member_ids: int) -> Conversation:
    conv = Conversation(
        type="group", title="Sched forum", created_by_user_id=creator_id
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
                can_change_info=is_creator,
                can_manage_members=is_creator,
                can_manage_posting_permissions=is_creator,
                can_delete_messages=is_creator,
                can_pin_messages=is_creator,
                can_invite_users=is_creator,
                can_manage_video_chats=is_creator,
            )
        )
    db.flush()
    return conv


def test_schedule_and_dispatch_keeps_effect(db_session):
    _users(db_session, 1, 2)
    conv = _direct(db_session, 1, 2)
    svc = ChatService(db_session)
    send_at = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5)
    item = svc.schedule_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="boom later",
        send_at=send_at,
        effect_id="confetti",
    )
    db_session.commit()
    assert item.effect_id == "confetti"

    # Force due.
    item.send_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=1)
    db_session.commit()
    sent = svc.dispatch_scheduled_messages(conv.id)
    assert len(sent) == 1
    assert sent[0].effect_id == "confetti"
    assert sent[0].content == "boom later"


def test_schedule_forum_topic_and_dispatch(db_session):
    _users(db_session, 1, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    svc.set_group_is_forum(conv.id, 1, True)
    news = svc.create_forum_topic(conv.id, 1, title="News")
    send_at = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5)
    item = svc.schedule_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="topic later",
        send_at=send_at,
        topic_id=news.id,
        effect_id="hearts",
    )
    db_session.commit()
    assert item.topic_id == news.id
    assert item.effect_id == "hearts"

    item.send_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=1)
    db_session.commit()
    sent = svc.dispatch_scheduled_messages(conv.id)
    assert len(sent) == 1
    assert sent[0].topic_id == news.id
    assert sent[0].effect_id == "hearts"


def test_schedule_rejects_invalid_effect(db_session):
    _users(db_session, 1, 2)
    conv = _direct(db_session, 1, 2)
    svc = ChatService(db_session)
    send_at = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5)
    with pytest.raises(ValueError, match="effect_id_invalid"):
        svc.schedule_message(
            conversation_id=conv.id,
            sender_id=1,
            msg_type="text",
            content="nope",
            send_at=send_at,
            effect_id="laser_unicorn",
        )
