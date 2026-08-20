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
from app.api.v1 import gifs as gifs_api
from app.api.v1 import stories as stories_api
from app.api.v1 import users as users_api
from app.core.database import Base
from app.models.chat_folder import ChatFolder, ChatFolderItem
from app.models.chat_folder_share import ChatFolderShare
from app.models.close_friend import CloseFriend
from app.models.conversation import Contact, Conversation, ConversationMember
from app.models.follower import Follower
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.gif_favorite import GifFavorite
from app.models.quick_reply import QuickReply
from app.models.story import Story, StoryReaction
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
            ChatFolder.__table__,
            ChatFolderItem.__table__,
            ChatFolderShare.__table__,
            GifFavorite.__table__,
            QuickReply.__table__,
            Story.__table__,
            StoryReaction.__table__,
            Follower.__table__,
            CloseFriend.__table__,
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


def _activate(db, user_id: int, level: int) -> None:
    flex = FlexSubscriptionService(db)
    flex.ensure_catalog()
    flex.activate(user_id, level)
    db.commit()


def test_level_52_does_not_unlock_blocks_n_o(db_session):
    _user(db_session, 1)
    _activate(db_session, 1, 52)
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "edit_history") is True
    assert billing.has_feature(1, "gif_favorites") is False
    assert billing.has_feature(1, "story_archive") is False
    assert billing.has_feature(1, "story_tray_priority") is False
    assert billing.has_feature(1, "group_add_privacy") is False
    assert billing.has_feature(1, "folder_share") is False
    assert billing.has_feature(1, "story_caption_plus") is False
    assert billing.has_feature(1, "animated_avatar") is False
    assert billing.has_feature(1, "quick_replies") is False


def test_gif_favorites_toggle_requires_feature(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 52)
    empty = asyncio.run(
        gifs_api.list_gif_favorites(current_user=owner, db=db_session)
    )
    assert empty["items"] == []
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            gifs_api.toggle_gif_favorite(
                body={"media_url": "https://cdn.test/a.gif"},
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    _activate(db_session, 1, 53)
    added = asyncio.run(
        gifs_api.toggle_gif_favorite(
            body={"media_url": "https://cdn.test/a.gif"},
            current_user=owner,
            db=db_session,
        )
    )
    assert added["favorited"] is True
    listed = asyncio.run(
        gifs_api.list_gif_favorites(current_user=owner, db=db_session)
    )
    assert listed["items"][0]["media_url"] == "https://cdn.test/a.gif"


def test_story_archive_keeps_expired(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 53)
    with pytest.raises(HTTPException) as err:
        asyncio.run(stories_api.list_story_archive(current_user=owner, db=db_session))
    assert err.value.status_code == 403
    _activate(db_session, 1, 54)
    now = datetime.utcnow()
    created = asyncio.run(
        stories_api.create_story(
            payload=stories_api.StoryCreateRequest(
                media_url="https://cdn.test/s.jpg",
                media_type="image",
            ),
            current_user=owner,
            db=db_session,
        )
    )
    story = db_session.query(Story).filter(Story.id == created.id).first()
    assert story.keep_in_archive is True
    story.expires_at = now - timedelta(hours=1)
    db_session.commit()
    archived = asyncio.run(
        stories_api.list_story_archive(current_user=owner, db=db_session)
    )
    assert len(archived) == 1
    assert archived[0].id == created.id


def test_story_tray_priority_sorts_authors_first(db_session):
    viewer = _user(db_session, 1)
    regular = _user(db_session, 2)
    premium = _user(db_session, 3)
    _activate(db_session, 3, 55)
    now = datetime.utcnow()
    db_session.add_all(
        [
            Story(
                user_id=regular.id,
                media_url="https://cdn.test/r.jpg",
                media_type="image",
                visibility="public",
                created_at=now,
                expires_at=now + timedelta(hours=12),
                user=regular,
            ),
            Story(
                user_id=premium.id,
                media_url="https://cdn.test/p.jpg",
                media_type="image",
                visibility="public",
                created_at=now - timedelta(minutes=5),
                expires_at=now + timedelta(hours=12),
                user=premium,
            ),
        ]
    )
    db_session.commit()
    feed = asyncio.run(
        stories_api.list_active_stories(current_user=viewer, db=db_session)
    )
    assert feed[0].user_id == premium.id
    assert feed[1].user_id == regular.id


def test_group_add_privacy_denied_and_reset_free(db_session):
    owner = _user(db_session, 1)
    target = _user(db_session, 2)
    friend = _user(db_session, 3)
    _activate(db_session, 1, 52)
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            users_api.update_user_profile(
                request=UpdateUserRequest(group_add_privacy="nobody"),
                current_user=target,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    _activate(db_session, 2, 56)
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(group_add_privacy="nobody"),
            current_user=target,
            db=db_session,
        )
    )
    chat = ChatService(db_session)
    group = chat.create_group(owner.id, "Команда", [friend.id])
    db_session.commit()
    with pytest.raises(ValueError, match="group_add_privacy_denied"):
        chat.add_group_members(group.id, owner.id, [target.id])
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(group_add_privacy="everybody"),
            current_user=target,
            db=db_session,
        )
    )
    added = chat.add_group_members(group.id, owner.id, [target.id])
    assert added == 1


def test_folder_share_and_import(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    _activate(db_session, 1, 56)
    chat = ChatService(db_session)
    folder = ChatFolder(user_id=owner.id, name="Работа", position=0)
    db_session.add(folder)
    db_session.commit()
    db_session.refresh(folder)
    with pytest.raises(ValueError, match="folder_share_required"):
        chat.share_folder(owner.id, folder.id)
    _activate(db_session, 1, 57)
    _activate(db_session, 2, 57)
    shared = chat.share_folder(owner.id, folder.id)
    db_session.commit()
    assert shared["token"]
    imported = chat.import_shared_folder(peer.id, shared["token"])
    db_session.commit()
    assert imported["name"] == "Работа"
    assert imported["id"] != folder.id


def test_story_caption_plus_and_gif_avatar_gated(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 57)
    long_caption = "x" * 501
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            stories_api.create_story(
                payload=stories_api.StoryCreateRequest(
                    media_url="https://cdn.test/c.jpg",
                    media_type="image",
                    caption=long_caption,
                ),
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    with pytest.raises(HTTPException) as avatar_err:
        asyncio.run(
            users_api.update_user_profile(
                request=UpdateUserRequest(avatar_url="https://cdn.test/me.gif"),
                current_user=owner,
                db=db_session,
            )
        )
    assert avatar_err.value.status_code == 403
    _activate(db_session, 1, 60)
    story = asyncio.run(
        stories_api.create_story(
            payload=stories_api.StoryCreateRequest(
                media_url="https://cdn.test/c2.jpg",
                media_type="image",
                caption=long_caption,
            ),
            current_user=owner,
            db=db_session,
        )
    )
    assert story.caption == long_caption
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(avatar_url="https://cdn.test/me.gif"),
            current_user=owner,
            db=db_session,
        )
    )
    db_session.refresh(owner)
    assert owner.avatar_url.endswith(".gif")


def test_quick_replies_create_requires_feature(db_session):
    owner = _user(db_session, 1)
    _activate(db_session, 1, 59)
    empty = asyncio.run(
        chats_api.list_quick_replies(current_user=owner, db=db_session)
    )
    assert empty["items"] == []
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            chats_api.create_quick_reply(
                body={"title": "Привет", "text": "Добрый день"},
                current_user=owner,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    _activate(db_session, 1, 60)
    created = asyncio.run(
        chats_api.create_quick_reply(
            body={"title": "Привет", "text": "Добрый день"},
            current_user=owner,
            db=db_session,
        )
    )
    assert created["text"] == "Добрый день"
    listed = asyncio.run(
        chats_api.list_quick_replies(current_user=owner, db=db_session)
    )
    assert len(listed["items"]) == 1
