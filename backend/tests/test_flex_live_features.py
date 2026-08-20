import asyncio
import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from fastapi import HTTPException

from app.api.v1 import chats as chats_api
from app.api.v1 import stories as stories_api
from app.schemas.chat import CreateChatTagRequest, SetConversationTagsRequest
from app.core.database import Base
from app.models.chat_tag import ChatTag, ConversationChatTag
from app.models.conversation import Contact, Conversation, ConversationMember
from app.models.user_block import UserBlock
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.story import Story, StoryReaction, StoryView
from app.models.subscription import Subscription
from app.models.user import User
from app.services.chat_service import ChatService
from app.services.chat_tag_service import ChatTagError, create_tag, set_conversation_tags
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
            Story.__table__,
            StoryView.__table__,
            StoryReaction.__table__,
            ChatTag.__table__,
            ConversationChatTag.__table__,
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


def test_level_44_does_not_unlock_block_l(db_session):
    _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 44)
    db_session.commit()
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "call_privacy") is True
    assert billing.has_feature(1, "extra_pinned_chats") is False
    assert billing.has_feature(1, "story_download") is False
    assert billing.has_feature(1, "auto_translate") is False
    assert billing.has_feature(1, "chat_tags") is False


def test_extra_pinned_chats_limit(db_session):
    owner = _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 1)
    db_session.commit()
    chat = ChatService(db_session)
    for peer_id in range(2, 8):
        _user(db_session, peer_id)
        conv = chat.get_or_create_direct(owner.id, peer_id)
        if peer_id <= 6:
            chat.set_pinned(conv.id, owner.id, True)
        else:
            with pytest.raises(ValueError, match="pinned_chat_limit"):
                chat.set_pinned(conv.id, owner.id, True)
    flex.activate(1, 45)
    db_session.commit()
    last = chat.get_or_create_direct(owner.id, 7)
    chat.set_pinned(last.id, owner.id, True)


def test_auto_translate_requires_feature(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 1)
    db_session.commit()
    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(owner.id, peer.id)
    with pytest.raises(ValueError, match="auto_translate_required"):
        chat.set_auto_translate(conv.id, owner.id, True)
    chat.set_auto_translate(conv.id, owner.id, False)
    flex.activate(1, 47)
    db_session.commit()
    chat.set_auto_translate(conv.id, owner.id, True)
    member = (
        db_session.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conv.id,
            ConversationMember.user_id == owner.id,
        )
        .first()
    )
    assert member.auto_translate is True


def test_chat_tags_assign(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 47)
    db_session.commit()
    chat = ChatService(db_session)
    conv = chat.get_or_create_direct(owner.id, peer.id)
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            chats_api.create_chat_tag(
                body=CreateChatTagRequest(title="Работа", color="red"),
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    flex.activate(1, 48)
    db_session.commit()
    created = asyncio.run(
        chats_api.create_chat_tag(
            body=CreateChatTagRequest(title="Работа", color="red"),
            current_user=owner,
            db=db_session,
        )
    )
    assigned = asyncio.run(
        chats_api.set_chat_tags(
            conversation_id=conv.id,
            body=SetConversationTagsRequest(tag_ids=[created.id]),
            current_user=owner,
            db=db_session,
        )
    )
    assert assigned["tag_ids"] == [created.id]
    with pytest.raises(ChatTagError, match="bad_tag_color"):
        create_tag(db_session, owner.id, "Сломанная", "gold")
    ids = set_conversation_tags(db_session, owner.id, conv.id, [created.id])
    assert ids == [created.id]


def test_story_download_requires_feature(db_session):
    owner = _user(db_session, 1)
    viewer = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(2, 1)
    db_session.commit()
    story = Story(
        user_id=owner.id,
        media_url="https://cdn.example/s.jpg",
        media_type="image",
        visibility="public",
        expires_at=datetime.utcnow() + timedelta(hours=12),
        created_at=datetime.utcnow(),
    )
    db_session.add(story)
    db_session.commit()
    db_session.refresh(story)
    story.user = owner

    with pytest.raises(Exception):
        asyncio.run(
            stories_api.save_story(
                story_id=story.id,
                current_user=viewer,
                db=db_session,
            )
        )
    flex.activate(2, 46)
    db_session.commit()
    result = asyncio.run(
        stories_api.save_story(
            story_id=story.id,
            current_user=viewer,
            db=db_session,
        )
    )
    assert result["media_url"] == "https://cdn.example/s.jpg"
