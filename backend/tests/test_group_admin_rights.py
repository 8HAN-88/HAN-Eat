"""Granular Telegram-like group admin rights."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from datetime import datetime, timedelta, timezone

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
    MessageHide,
)
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
            ConversationPinnedMessage.__table__,
            MessageHide.__table__,
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
        email=f"u{user_id}@rights.test",
        password_hash="h",
        name=f"U{user_id}",
    )
    db.add(u)
    db.flush()
    return u


def _group(db, creator_id: int, *member_ids: int) -> Conversation:
    conv = Conversation(
        type="group", title="Rights", created_by_user_id=creator_id
    )
    db.add(conv)
    db.flush()
    all_ids = (creator_id,) + member_ids
    for uid in all_ids:
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


def test_pin_requires_can_pin_messages(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    msg = Message(
        conversation_id=conv.id,
        sender_id=2,
        type="text",
        content="hi",
    )
    db_session.add(msg)
    db_session.commit()

    svc = ChatService(db_session)
    with pytest.raises(ValueError, match="forbidden"):
        svc.set_pinned_message(conv.id, 2, msg.id, True)

    member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == 2,
        )
        .one()
    )
    member.is_admin = True
    member.can_pin_messages = True
    db_session.commit()

    pinned_id = svc.set_pinned_message(conv.id, 2, msg.id, True)
    assert pinned_id == msg.id


def test_admin_can_delete_others_messages(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    _user(db_session, 3)
    _user(db_session, 4)
    conv = _group(db_session, 1, 2, 3, 4)
    old = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=10)
    msg = Message(
        conversation_id=conv.id,
        sender_id=3,
        type="text",
        content="old",
        created_at=old,
    )
    db_session.add(msg)
    db_session.flush()

    mod = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == 2,
        )
        .one()
    )
    mod.is_admin = True
    mod.can_delete_messages = True
    db_session.commit()

    svc = ChatService(db_session)
    # Regular peer cannot delete someone else's message for everyone.
    with pytest.raises(ValueError, match="forbidden"):
        svc.delete_message(conv.id, msg.id, 4, scope="all")
    # Sender of old message still hits the 48h limit.
    with pytest.raises(ValueError, match="too_old"):
        svc.delete_message(conv.id, msg.id, 3, scope="all")

    applied = svc.delete_message(conv.id, msg.id, 2, scope="all")
    assert applied == "all"
    db_session.refresh(msg)
    assert msg.deleted_at is not None


def test_change_info_separated_from_posting_permissions(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == 2,
        )
        .one()
    )
    member.is_admin = True
    member.can_manage_posting_permissions = True
    member.can_change_info = False
    db_session.commit()

    svc = ChatService(db_session)
    with pytest.raises(ValueError, match="forbidden"):
        svc.update_group_title(conv.id, 2, "Nope")

    member.can_change_info = True
    db_session.commit()
    updated = svc.update_group_title(conv.id, 2, "Yes")
    assert updated.title == "Yes"


def test_set_permissions_granular_flags(db_session):
    _user(db_session, 1)
    _user(db_session, 2)
    conv = _group(db_session, 1, 2)
    svc = ChatService(db_session)
    svc.set_group_member_admin(conv.id, 1, 2, True)
    db_session.flush()
    member = svc.set_group_member_permissions(
        conv.id,
        1,
        2,
        can_manage_members=False,
        can_manage_posting_permissions=False,
        can_change_info=True,
        can_delete_messages=True,
        can_pin_messages=False,
        can_invite_users=True,
        can_manage_video_chats=False,
    )
    assert member.can_change_info is True
    assert member.can_delete_messages is True
    assert member.can_pin_messages is False
    assert member.can_invite_users is True
    assert member.can_manage_video_chats is False
