import asyncio
import os
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import users as users_api
from app.core.database import Base
from app.models.conversation import Contact, Conversation, ConversationMember, Message
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexGift,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.notification import Notification
from app.models.subscription import Subscription
from app.models.user import User
from app.models.user_block import UserBlock
from app.models.user_business import BusinessAutoReply, UserBusinessSettings
from app.schemas.user import UpdateUserRequest
from app.services.business_profile_service import (
    is_open_now,
    normalize_hours,
    owner_settings_payload,
    public_payload,
    update_settings,
)
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
            UserBusinessSettings.__table__,
            BusinessAutoReply.__table__,
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


def _inbound(db, owner: User, peer: User, text: str = "Привет") -> list[Message]:
    chat = ChatService(db)
    conv = chat.get_or_create_direct(peer.id, owner.id)
    db.commit()
    chat.send_message(
        conversation_id=conv.id,
        sender_id=peer.id,
        msg_type="text",
        content=text,
        notify=False,
    )
    db.commit()
    return (
        db.query(Message)
        .filter(Message.conversation_id == conv.id, Message.sender_id == owner.id)
        .order_by(Message.id.asc())
        .all()
    )


def test_level_60_does_not_unlock_blocks_p_q(db_session):
    _user(db_session, 1)
    _activate(db_session, 1, 60)
    billing = SubscriptionService(db_session)
    assert billing.has_feature(1, "quick_replies") is True
    assert billing.has_feature(1, "business_greeting") is False
    assert billing.has_feature(1, "business_away") is False
    assert billing.has_feature(1, "business_hours") is False
    assert billing.has_feature(1, "business_location") is False
    assert billing.has_feature(1, "business_intro") is False
    assert billing.has_feature(1, "business_bot") is False
    assert billing.has_feature(1, "dm_privacy") is False
    assert billing.has_feature(1, "profile_website") is False


def test_greeting_first_inbound_and_cooldown(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    _activate(db_session, 1, 60)
    with pytest.raises(HTTPException) as err:
        update_settings(
            db_session,
            owner,
            {"greeting_enabled": True, "greeting_text": "Здравствуйте"},
        )
    assert err.value.status_code == 403
    _activate(db_session, 1, 61)
    update_settings(
        db_session,
        owner,
        {"greeting_enabled": True, "greeting_text": "Здравствуйте"},
    )
    db_session.commit()
    first = _inbound(db_session, owner, peer)
    assert [m.content for m in first] == ["Здравствуйте"]
    second = _inbound(db_session, owner, peer, "Ещё раз")
    assert [m.content for m in second] == ["Здравствуйте"]


def test_away_outside_hours(db_session):
    owner = _user(db_session, 1)
    peer = _user(db_session, 2)
    _activate(db_session, 1, 63)
    closed_dow = (datetime.now(timezone.utc).weekday() + 1) % 7
    update_settings(
        db_session,
        owner,
        {
            "away_enabled": True,
            "away_text": "Сейчас нас нет",
            "away_mode": "outside_hours",
            "hours": {
                "timezone": "UTC",
                "intervals": [{"dow": closed_dow, "start": "09:00", "end": "18:00"}],
            },
        },
    )
    db_session.commit()
    replies = _inbound(db_session, owner, peer)
    assert [m.content for m in replies] == ["Сейчас нас нет"]


def test_hours_is_open_now():
    monday_open = datetime(2026, 8, 17, 10, 0, tzinfo=timezone.utc)
    hours = normalize_hours(
        {
            "timezone": "UTC",
            "intervals": [{"dow": 0, "start": "09:00", "end": "18:00"}],
        }
    )
    assert is_open_now(hours, monday_open) is True
    assert is_open_now(hours, monday_open.replace(hour=20)) is False


def test_location_intro_bot_website_gated(db_session):
    owner = _user(db_session, 1)
    bot = _user(
        db_session,
        9,
        is_bot=True,
        bot_username="helpbot",
        created_by_user_id=1,
    )
    _activate(db_session, 1, 63)
    with pytest.raises(HTTPException) as loc_err:
        update_settings(
            db_session,
            owner,
            {"location_lat": 55.75, "location_lng": 37.61, "location_address": "Москва"},
        )
    assert loc_err.value.status_code == 403
    with pytest.raises(HTTPException) as intro_err:
        update_settings(
            db_session,
            owner,
            {"intro_title": "Кафе", "intro_text": "Ждём вас"},
        )
    assert intro_err.value.status_code == 403
    with pytest.raises(HTTPException) as bot_err:
        update_settings(db_session, owner, {"support_bot_id": bot.id})
    assert bot_err.value.status_code == 403
    with pytest.raises(HTTPException) as web_err:
        update_settings(db_session, owner, {"website_url": "https://haneat.app"})
    assert web_err.value.status_code == 403

    _activate(db_session, 1, 68)
    update_settings(
        db_session,
        owner,
        {
            "location_lat": 55.75,
            "location_lng": 37.61,
            "location_address": "Москва",
            "intro_title": "Кафе",
            "intro_text": "Ждём вас",
            "support_bot_id": bot.id,
            "website_url": "haneat.app",
            "hours": {
                "timezone": "UTC",
                "intervals": [{"dow": 0, "start": "09:00", "end": "18:00"}],
            },
        },
    )
    db_session.commit()
    public = public_payload(db_session, owner)
    assert public["location"]["address"] == "Москва"
    assert public["intro"]["title"] == "Кафе"
    assert public["support_bot"]["id"] == bot.id
    assert public["website_url"] == "https://haneat.app"
    assert public["hours"]["intervals"][0]["start"] == "09:00"

    update_settings(
        db_session,
        owner,
        {
            "location_lat": None,
            "location_lng": None,
            "intro_title": "",
            "intro_text": "",
            "support_bot_id": None,
            "website_url": "",
            "hours": {"timezone": "UTC", "intervals": []},
        },
    )
    db_session.commit()
    cleared = public_payload(db_session, owner)
    assert "location" not in cleared
    assert "intro" not in cleared
    assert "support_bot" not in cleared
    assert "website_url" not in cleared
    assert "hours" not in cleared


def test_dm_privacy_blocks_new_chat_and_reset_is_free(db_session):
    owner = _user(db_session, 1)
    target = _user(db_session, 2)
    friend = _user(db_session, 3)
    _activate(db_session, 2, 66)
    with pytest.raises(HTTPException) as err:
        asyncio.run(
            users_api.update_user_profile(
                request=UpdateUserRequest(dm_privacy="nobody"),
                current_user=target,
                db=db_session,
            )
        )
    assert err.value.status_code == 403
    _activate(db_session, 2, 67)
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(dm_privacy="nobody"),
            current_user=target,
            db=db_session,
        )
    )
    chat = ChatService(db_session)
    with pytest.raises(ValueError, match="dm_privacy_denied"):
        chat.get_or_create_direct(owner.id, target.id)
    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(dm_privacy="everybody"),
            current_user=target,
            db=db_session,
        )
    )
    conv = chat.get_or_create_direct(owner.id, target.id)
    db_session.commit()
    assert conv.id > 0

    asyncio.run(
        users_api.update_user_profile(
            request=UpdateUserRequest(dm_privacy="contacts"),
            current_user=target,
            db=db_session,
        )
    )
    with pytest.raises(ValueError, match="dm_privacy_denied"):
        chat.get_or_create_direct(friend.id, target.id)
    existing = chat.get_or_create_direct(owner.id, target.id)
    assert existing.id == conv.id
    listed = owner_settings_payload(db_session, target)
    assert listed["dm_privacy"] == "contacts"
