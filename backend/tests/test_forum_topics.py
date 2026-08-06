"""Group forums / topics MVP."""
import os

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


def _user(db, user_id: int) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@forum.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _group(db, creator_id: int, *member_ids: int) -> Conversation:
    conv = Conversation(
        type="group", title="Forum", created_by_user_id=creator_id
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
                can_manage_members=is_creator,
                can_manage_posting_permissions=is_creator,
                can_change_info=is_creator,
                can_delete_messages=is_creator,
                can_pin_messages=is_creator,
                can_invite_users=is_creator,
                can_manage_video_chats=is_creator,
            )
        )
    db.flush()
    return conv


def test_enable_forum_creates_general(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    svc.set_group_is_forum(conv.id, 1, True)
    db_session.commit()
    db_session.refresh(conv)
    assert conv.is_forum is True
    topics = svc.list_forum_topics(conv.id, 1)
    assert len(topics) == 1
    assert topics[0].is_general is True
    assert topics[0].title == "General"


def test_send_and_filter_by_topic(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    # Pre-forum message (shows under General).
    pre, _ = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="before forum",
    )
    svc.set_group_is_forum(conv.id, 1, True)
    general = svc.ensure_general_topic(conv.id, 1)
    news = svc.create_forum_topic(conv.id, 1, title="News", icon_emoji="📰")
    general_msg, _ = svc.send_message(
        conversation_id=conv.id,
        sender_id=1,
        msg_type="text",
        content="in general",
        topic_id=general.id,
    )
    news_msg, _ = svc.send_message(
        conversation_id=conv.id,
        sender_id=2,
        msg_type="text",
        content="in news",
        topic_id=news.id,
    )
    db_session.commit()

    general_items, _ = svc.get_messages(conv.id, 1, topic_id=general.id)
    general_ids = {m.id for m in general_items}
    assert pre.id in general_ids
    assert general_msg.id in general_ids
    assert news_msg.id not in general_ids

    news_items, _ = svc.get_messages(conv.id, 1, topic_id=news.id)
    news_ids = {m.id for m in news_items}
    assert news_msg.id in news_ids
    assert general_msg.id not in news_ids
    assert pre.id not in news_ids


def test_closed_topic_rejects_send(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    svc.set_group_is_forum(conv.id, 1, True)
    topic = svc.create_forum_topic(conv.id, 1, title="Closed soon")
    svc.update_forum_topic(conv.id, 1, topic.id, closed=True)
    db_session.commit()
    with pytest.raises(ValueError, match="topic_closed"):
        svc.send_message(
            conversation_id=conv.id,
            sender_id=2,
            msg_type="text",
            content="nope",
            topic_id=topic.id,
        )


def test_member_cannot_create_topic(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    svc.set_group_is_forum(conv.id, 1, True)
    with pytest.raises(ValueError, match="forbidden"):
        svc.create_forum_topic(conv.id, 2, title="Hack")
