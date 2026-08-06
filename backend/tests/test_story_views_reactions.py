"""Story viewers list + emoji reactions."""
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
        email=f"u{uid}@story.test",
        password_hash="h",
        name=name,
        username=f"user{uid}",
    )
    db.add(u)
    db.flush()
    return u


def _story(db, owner: User) -> Story:
    story = Story(
        user_id=owner.id,
        media_url="https://cdn.example/s.jpg",
        media_type="image",
        visibility="public",
        expires_at=datetime.utcnow() + timedelta(hours=12),
    )
    db.add(story)
    db.commit()
    db.refresh(story)
    story.user = owner
    return story


@pytest.mark.asyncio
async def test_mark_viewed_dedupes_and_counts(db_session):
    owner = _user(db_session, 1, "Owner")
    viewer = _user(db_session, 2, "Viewer")
    story = _story(db_session, owner)

    first = await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )
    second = await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )
    assert first.views_count == 1
    assert second.views_count == 1
    assert db_session.query(StoryView).count() == 1


@pytest.mark.asyncio
async def test_owner_view_does_not_count(db_session):
    owner = _user(db_session, 1, "Owner")
    story = _story(db_session, owner)
    result = await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=owner,
        db=db_session,
    )
    assert result.views_count == 0
    assert db_session.query(StoryView).count() == 0


@pytest.mark.asyncio
async def test_list_viewers_owner_only(db_session):
    owner = _user(db_session, 1, "Owner")
    viewer = _user(db_session, 2, "Viewer")
    story = _story(db_session, owner)
    await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )

    with pytest.raises(HTTPException) as forbidden:
        await stories_api.list_story_viewers(
            story_id=story.id,
            current_user=viewer,
            db=db_session,
        )
    assert forbidden.value.status_code == 403

    payload = await stories_api.list_story_viewers(
        story_id=story.id,
        current_user=owner,
        db=db_session,
    )
    assert payload.views_count == 1
    assert len(payload.items) == 1
    assert payload.items[0].user.id == viewer.id


@pytest.mark.asyncio
async def test_set_and_toggle_reaction(db_session):
    owner = _user(db_session, 1, "Owner")
    viewer = _user(db_session, 2, "Viewer")
    story = _story(db_session, owner)

    with pytest.raises(HTTPException) as own:
        await stories_api.set_story_reaction(
            story_id=story.id,
            payload=stories_api.StoryReactionRequest(emoji="❤️"),
            current_user=owner,
            db=db_session,
        )
    assert own.value.status_code == 400

    reacted = await stories_api.set_story_reaction(
        story_id=story.id,
        payload=stories_api.StoryReactionRequest(emoji="❤️"),
        current_user=viewer,
        db=db_session,
    )
    assert reacted.my_reaction == "❤️"
    assert reacted.reactions[0].emoji == "❤️"
    assert reacted.reactions[0].count == 1

    toggled_off = await stories_api.set_story_reaction(
        story_id=story.id,
        payload=stories_api.StoryReactionRequest(emoji="❤️"),
        current_user=viewer,
        db=db_session,
    )
    assert toggled_off.my_reaction is None
    assert toggled_off.reactions == []

    await stories_api.set_story_reaction(
        story_id=story.id,
        payload=stories_api.StoryReactionRequest(emoji="🔥"),
        current_user=viewer,
        db=db_session,
    )
    viewers = await stories_api.list_story_viewers(
        story_id=story.id,
        current_user=owner,
        db=db_session,
    )
    # No view yet — reaction alone does not create a view row.
    assert viewers.items == []

    await stories_api.mark_story_viewed(
        story_id=story.id,
        current_user=viewer,
        db=db_session,
    )
    viewers = await stories_api.list_story_viewers(
        story_id=story.id,
        current_user=owner,
        db=db_session,
    )
    assert viewers.items[0].reaction == "🔥"
