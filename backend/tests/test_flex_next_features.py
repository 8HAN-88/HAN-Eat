import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1.stories import StoryCreateRequest
from app.api.v1 import stories as stories_api
from app.core.database import Base
from app.models.conversation import Contact
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.sticker import Sticker, StickerPack, StickerPackInstall
from app.models.story import Story, StoryReaction, StoryView
from app.models.subscription import Subscription
from app.models.user import User
from app.services.call_privacy import can_call_user, normalize_call_privacy
from app.services.flex_subscription_service import FlexSubscriptionService
from app.services.sticker_service import StickerService
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
            Story.__table__,
            StoryView.__table__,
            StoryReaction.__table__,
            StickerPack.__table__,
            Sticker.__table__,
            StickerPackInstall.__table__,
            Contact.__table__,
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


def _story(db, owner: User) -> Story:
    story = Story(
        user_id=owner.id,
        media_url="https://cdn.example/s.jpg",
        media_type="image",
        visibility="public",
        expires_at=datetime.utcnow() + timedelta(hours=12),
        created_at=datetime.utcnow(),
    )
    db.add(story)
    db.commit()
    db.refresh(story)
    story.user = owner
    return story


def test_normalize_call_privacy():
    assert normalize_call_privacy("Everybody") == "everybody"
    assert normalize_call_privacy("contacts") == "contacts"
    assert normalize_call_privacy("nobody") == "nobody"
    with pytest.raises(ValueError, match="invalid_call_privacy"):
        normalize_call_privacy("friends")


def test_can_call_user_privacy(db_session):
    caller = _user(db_session, 1)
    callee = _user(db_session, 2, call_privacy="everybody")
    assert can_call_user(db_session, caller.id, callee) is True

    callee.call_privacy = "nobody"
    db_session.commit()
    assert can_call_user(db_session, caller.id, callee) is False
    assert can_call_user(db_session, callee.id, callee) is True

    callee.call_privacy = "contacts"
    db_session.commit()
    assert can_call_user(db_session, caller.id, callee) is False
    db_session.add(Contact(owner_user_id=callee.id, contact_user_id=caller.id))
    db_session.commit()
    assert can_call_user(db_session, caller.id, callee) is True


def test_level_40_does_not_unlock_block_k(db_session):
    _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 40)
    db_session.commit()
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "archive_non_contacts") is True
    assert billing.has_feature(1, "story_stealth") is False
    assert billing.has_feature(1, "longer_stories") is False
    assert billing.has_feature(1, "premium_stickers") is False
    assert billing.has_feature(1, "call_privacy") is False

    flex.activate(1, 44)
    db_session.commit()
    assert billing.has_feature(1, "story_stealth") is True
    assert billing.has_feature(1, "longer_stories") is True
    assert billing.has_feature(1, "premium_stickers") is True
    assert billing.has_feature(1, "call_privacy") is True


@pytest.mark.asyncio
async def test_story_stealth_skips_view_row(db_session):
    owner = _user(db_session, 1)
    viewer = _user(db_session, 2, story_stealth=True)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(2, 41)
    db_session.commit()
    story = _story(db_session, owner)

    result = await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )
    assert result.views_count == 0
    assert db_session.query(StoryView).count() == 0


@pytest.mark.asyncio
async def test_story_stealth_without_feature_still_counts(db_session):
    owner = _user(db_session, 1)
    viewer = _user(db_session, 2, story_stealth=True)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(2, 1)
    db_session.commit()
    story = _story(db_session, owner)

    result = await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )
    assert result.views_count == 1
    assert db_session.query(StoryView).count() == 1


@pytest.mark.asyncio
async def test_longer_stories_sets_48h_expiry(db_session):
    user = _user(db_session, 1)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 1)
    db_session.commit()
    payload = StoryCreateRequest(
        media_url="https://cdn.example/s.jpg",
        media_type="image",
    )
    before = datetime.utcnow()
    free = await stories_api.create_story(
        payload, current_user=user, db=db_session
    )
    free_delta = datetime.fromisoformat(free.expires_at) - before
    assert timedelta(hours=23, minutes=50) <= free_delta <= timedelta(hours=24, minutes=10)

    flex.activate(1, 42)
    db_session.commit()
    before = datetime.utcnow()
    long = await stories_api.create_story(
        payload, current_user=user, db=db_session
    )
    long_delta = datetime.fromisoformat(long.expires_at) - before
    assert timedelta(hours=47, minutes=50) <= long_delta <= timedelta(hours=48, minutes=10)


def test_premium_stickers_gated(db_session):
    owner = _user(db_session, 1)
    other = _user(db_session, 2)
    flex = FlexSubscriptionService(db_session)
    flex.ensure_catalog()
    flex.activate(1, 43)
    db_session.commit()
    stickers = StickerService(db_session)

    with pytest.raises(ValueError, match="premium_sticker"):
        stickers.create_pack(other.id, "Nope", True, is_premium=True)

    pack = stickers.create_pack(owner.id, "Gold", True, is_premium=True)
    item = stickers.add_sticker(
        user_id=owner.id,
        pack_id=pack.id,
        media_url="https://cdn.example/gold.webp",
    )
    db_session.commit()

    stickers.require_sticker_send(owner.id, item.media_url)
    with pytest.raises(ValueError, match="premium_sticker"):
        stickers.install_pack(other.id, pack.id)
    with pytest.raises(ValueError, match="premium_sticker"):
        stickers.require_sticker_send(other.id, item.media_url)
    stickers.require_sticker_send(other.id, "https://cdn.example/unknown.webp")

    free = stickers.create_pack(owner.id, "Free pack", True, is_premium=False)
    free_item = stickers.add_sticker(
        user_id=owner.id,
        pack_id=free.id,
        media_url="https://cdn.example/free.webp",
    )
    db_session.commit()
    stickers.install_pack(other.id, free.id)
    stickers.require_sticker_send(other.id, free_item.media_url)

    flex.activate(2, 43)
    db_session.commit()
    stickers.install_pack(other.id, pack.id)
    stickers.require_sticker_send(other.id, item.media_url)
