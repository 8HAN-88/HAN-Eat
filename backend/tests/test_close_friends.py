"""Close friends list + story visibility."""
import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import stories as stories_api
from app.api.v1 import users as users_api
from app.core.database import Base
from app.models.close_friend import CloseFriend
from app.models.follower import Follower
from app.models.story import Story, StoryReaction, StoryView
from app.models.user import User


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
            Follower.__table__,
            CloseFriend.__table__,
            Story.__table__,
            StoryView.__table__,
            StoryReaction.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, uid: int) -> User:
    u = User(
        id=uid,
        email=f"u{uid}@cf.test",
        password_hash="h",
        name=f"U{uid}",
        username=f"u{uid}",
    )
    db.add(u)
    db.flush()
    return u


@pytest.mark.asyncio
async def test_add_list_remove_close_friends(db_session):
    owner = _user(db_session, 1)
    friend = _user(db_session, 2)
    db_session.commit()

    await users_api.add_close_friend(
        friend_user_id=friend.id, current_user=owner, db=db_session
    )
    listed = await users_api.list_close_friends(
        current_user=owner, db=db_session
    )
    assert len(listed["items"]) == 1
    assert listed["items"][0]["id"] == friend.id

    await users_api.remove_close_friend(
        friend_user_id=friend.id, current_user=owner, db=db_session
    )
    listed2 = await users_api.list_close_friends(
        current_user=owner, db=db_session
    )
    assert listed2["items"] == []


@pytest.mark.asyncio
async def test_close_friends_story_visibility(db_session):
    owner = _user(db_session, 1)
    friend = _user(db_session, 2)
    stranger = _user(db_session, 3)
    db_session.add(
        CloseFriend(user_id=owner.id, friend_user_id=friend.id)
    )
    story = Story(
        user_id=owner.id,
        media_url="https://cdn.example/s.jpg",
        media_type="image",
        visibility="close_friends",
        expires_at=datetime.utcnow() + timedelta(hours=12),
    )
    db_session.add(story)
    db_session.commit()
    db_session.refresh(story)
    story.user = owner

    assert stories_api.can_view_story(story, friend, db_session)
    assert not stories_api.can_view_story(story, stranger, db_session)

    for_friend = await stories_api.list_active_stories(
        current_user=friend, db=db_session
    )
    for_stranger = await stories_api.list_active_stories(
        current_user=stranger, db=db_session
    )
    assert len(for_friend) == 1
    assert for_stranger == []


@pytest.mark.asyncio
async def test_cannot_add_self(db_session):
    owner = _user(db_session, 1)
    db_session.commit()
    with pytest.raises(HTTPException) as exc:
        await users_api.add_close_friend(
            friend_user_id=owner.id, current_user=owner, db=db_session
        )
    assert exc.value.status_code == 400
