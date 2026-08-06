"""Story visibility: public / followers / private."""
import os
from datetime import datetime, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import stories as stories_api
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


def _user(db, uid: int, name: str) -> User:
    u = User(
        id=uid,
        email=f"u{uid}@storypriv.test",
        password_hash="h",
        name=name,
        username=f"user{uid}",
    )
    db.add(u)
    db.flush()
    return u


def _story(db, owner: User, visibility: str) -> Story:
    story = Story(
        user_id=owner.id,
        media_url="https://cdn.example/s.jpg",
        media_type="image",
        visibility=visibility,
        expires_at=datetime.utcnow() + timedelta(hours=12),
    )
    db.add(story)
    db.commit()
    db.refresh(story)
    story.user = owner
    return story


def _follow(db, follower: User, followee: User) -> None:
    db.add(Follower(follower_id=follower.id, followee_id=followee.id))
    db.commit()


def test_can_view_matrix(db_session):
    owner = _user(db_session, 1, "Owner")
    follower = _user(db_session, 2, "Follower")
    stranger = _user(db_session, 3, "Stranger")
    _follow(db_session, follower, owner)

    public = _story(db_session, owner, "public")
    followers = _story(db_session, owner, "followers")
    private = _story(db_session, owner, "private")

    assert stories_api.can_view_story(public, stranger, db_session)
    assert stories_api.can_view_story(followers, follower, db_session)
    assert not stories_api.can_view_story(followers, stranger, db_session)
    assert stories_api.can_view_story(private, owner, db_session)
    assert not stories_api.can_view_story(private, follower, db_session)


@pytest.mark.asyncio
async def test_list_respects_visibility(db_session):
    owner = _user(db_session, 1, "Owner")
    follower = _user(db_session, 2, "Follower")
    stranger = _user(db_session, 3, "Stranger")
    _follow(db_session, follower, owner)
    _story(db_session, owner, "public")
    _story(db_session, owner, "followers")
    _story(db_session, owner, "private")

    for_follower = await stories_api.list_active_stories(
        current_user=follower, db=db_session
    )
    for_stranger = await stories_api.list_active_stories(
        current_user=stranger, db=db_session
    )
    for_owner = await stories_api.list_active_stories(
        current_user=owner, db=db_session
    )

    assert {s.visibility for s in for_follower} == {"public", "followers"}
    assert {s.visibility for s in for_stranger} == {"public"}
    assert {s.visibility for s in for_owner} == {"public", "followers", "private"}


@pytest.mark.asyncio
async def test_view_private_blocked(db_session):
    owner = _user(db_session, 1, "Owner")
    stranger = _user(db_session, 2, "Stranger")
    story = _story(db_session, owner, "private")
    with pytest.raises(HTTPException) as exc:
        await stories_api.mark_story_viewed(
            story_id=story.id,
            current_user=stranger,
            db=db_session,
        )
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_react_followers_requires_follow(db_session):
    owner = _user(db_session, 1, "Owner")
    stranger = _user(db_session, 2, "Stranger")
    story = _story(db_session, owner, "followers")
    with pytest.raises(HTTPException) as exc:
        await stories_api.set_story_reaction(
            story_id=story.id,
            payload=stories_api.StoryReactionRequest(emoji="🔥"),
            current_user=stranger,
            db=db_session,
        )
    assert exc.value.status_code == 404
