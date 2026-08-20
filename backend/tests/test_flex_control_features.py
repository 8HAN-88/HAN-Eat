import asyncio
import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import chats as chats_api
from app.api.v1 import users as users_api
from app.core.database import Base
from app.models.chat_folder import ChatFolder
from app.models.conversation import (
    Contact,
    Conversation,
    ConversationMember,
    Message,
    MessageEditHistory,
)
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.subscription import Subscription
from app.models.user import User
from app.models.user_block import UserBlock
from app.schemas.user import UpdateUserRequest
from app.services.chat_service import ChatService
from app.services.flex_subscription_service import FlexSubscriptionService
from app.services.subscription_service import SubscriptionService


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
            Subscription.__table__,
            SubscriptionFeatureBlock.__table__,
            SubscriptionFeature.__table__,
            UserFlexSubscription.__table__,
            UserFlexSlot.__table__,
            UserFlexGift.__table__,
            Conversation.__table__,
            ConversationMember.__table__,
            Contact.__table__,
            UserBlock.__table__,
            Message.__table__,
            MessageEditHistory.__table__,
            ChatFolder.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int, **kwargs) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
        **kwargs,
    )
    db.add(u)
    db.commit()
    return u


def test_level_48_does_not_unlock_block_m(db_session):
    _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 48)
    db_session.commit()
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "chat_tags") is True
    assert billing.has_feature(1, "default_folder") is False
    assert billing.has_feature(1, "hide_forward") is False
    assert billing.has_feature(1, "read_timestamps") is False
    assert billing.has_feature(1, "edit_history") is False


def test_default_folder_requires_feature(db_session):
    owner = _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 48)
    db_session.commit()
    folder = ChatFolder(user_id=owner.id, name="Работа", position=0)
    db_session.add(folder)
    db_session.commit()
    db_session.refresh(folder)
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            users_api.update_user_profile(
                request=UpdateUserRequest(default_folder_id=folder.id),
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(default_folder_id=0),
            current_user=owner,
            db=db_session,
        )
    )
    flex.activate(1, 49)
    db_session.commit()
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(default_folder_id=folder.id),
            current_user=owner,
            db=db_session,
        )
    )
    db_session.refresh(owner)
    assert owner.default_folder_id == folder.id


def test_hide_forward_requires_feature(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    other = _user(db_session, 3)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 49)
    db_session.commit()
    chat = ChatService(db_session)
    source = chat.get_or_create_direct(owner.id, peer.id)
    target = chat.get_or_create_direct(owner.id, other.id)
    msg, _ = chat.send_message(
        conversation_id=source.id,
        sender_id=peer.id,
        msg_type="text",
        content="секрет",
        notify=False,
    )
    with pytest.raises(ValueError, match="hide_forward_required"):
        chat.forward_message(
            target_conversation_id=target.id,
            source_conversation_id=source.id,
            message_id=msg.id,
            sender_id=owner.id,
            as_copy=True,
        )
    copied = chat.forward_message(
        target_conversation_id=target.id,
        source_conversation_id=source.id,
        message_id=msg.id,
        sender_id=owner.id,
        as_copy=False,
    )
    assert copied.forward_from_user_id == peer.id
    flex.activate(1, 50)
    db_session.commit()
    hidden = chat.forward_message(
        target_conversation_id=target.id,
        source_conversation_id=source.id,
        message_id=msg.id,
        sender_id=owner.id,
        as_copy=True,
    )
    assert hidden.forward_from_user_id is None
    assert hidden.forward_from_name is None


def test_read_timestamps_set_on_mark_read(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(owner.id, peer.id)
    msg, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=owner.id,
        msg_type="text",
        content="привет",
        notify=False,
    )
    chat.mark_read(conv.id, peer.id, msg.id)
    member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == peer.id,
        )
        .first()
    )
    assert member.last_read_message_id == msg.id
    assert member.last_read_at is not None


def test_edit_history_requires_feature(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 51)
    db_session.commit()
    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(owner.id, peer.id)
    msg, _ = chat.send_message(
        conversation_id=conv.id,
        sender_id=owner.id,
        msg_type="text",
        content="новое",
        notify=False,
    )
    db_session.add(
        MessageEditHistory(
            message_id=msg.id,
            editor_id=owner.id,
            previous_content="старое",
            edited_at=datetime.utcnow() - timedelta(minutes=1),
        )
    )
    db_session.commit()
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            chats_api.list_message_edits(
                conversation_id=conv.id,
                message_id=msg.id,
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    flex.activate(1, 52)
    db_session.commit()
    result = asyncio.run(
        chats_api.list_message_edits(
            conversation_id=conv.id,
            message_id=msg.id,
            current_user=owner,
            db=db_session,
        )
    )
    assert result.current_content == "новое"
    assert result.items[0].content == "старое"
