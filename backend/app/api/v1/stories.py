"""
API для Stories / Моментов.
"""
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, func, or_

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.close_friend import CloseFriend
from app.models.follower import Follower
from app.models.story import Story, StoryReaction, StoryView
from app.models.user import User

router = APIRouter(prefix="/stories", tags=["Stories"])

_VALID_VISIBILITY = frozenset({"public", "followers", "close_friends", "private"})


class StoryCreateRequest(BaseModel):
    media_url: str = Field(..., min_length=1, max_length=2000)
    thumbnail_url: Optional[str] = Field(None, max_length=2000)
    media_type: str = Field(..., pattern="^(image|video)$")
    caption: Optional[str] = Field(None, max_length=500)
    visibility: str = Field(
        "public",
        pattern="^(public|followers|close_friends|private)$",
    )


class StoryAuthorResponse(BaseModel):
    id: int
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None


class StoryReactionSummary(BaseModel):
    emoji: str
    count: int


class StoryReactionRequest(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=16)


class StoryResponse(BaseModel):
    id: int
    user_id: int
    media_url: str
    thumbnail_url: Optional[str]
    media_type: str
    caption: Optional[str]
    visibility: str
    views_count: int
    created_at: str
    expires_at: str
    author: StoryAuthorResponse
    reactions: List[StoryReactionSummary] = Field(default_factory=list)
    my_reaction: Optional[str] = None


class StoryViewerItem(BaseModel):
    user: StoryAuthorResponse
    viewed_at: str
    reaction: Optional[str] = None


class StoryViewersResponse(BaseModel):
    views_count: int
    items: List[StoryViewerItem]


def _active_story_query(db: Session):
    now = datetime.utcnow()
    return (
        db.query(Story)
        .options(joinedload(Story.user))
        .filter(
            Story.deleted_at.is_(None),
            Story.is_active == True,  # noqa: E712
            Story.expires_at > now,
        )
    )


def _author_response(user: User) -> StoryAuthorResponse:
    return StoryAuthorResponse(
        id=user.id,
        name=user.name,
        username=user.username,
        avatar_url=user.avatar_url,
    )


def _reaction_summaries(
    db: Session, story_id: int, viewer_id: Optional[int]
) -> tuple[list[StoryReactionSummary], Optional[str]]:
    rows = (
        db.query(StoryReaction.emoji, func.count(StoryReaction.id))
        .filter(StoryReaction.story_id == story_id)
        .group_by(StoryReaction.emoji)
        .all()
    )
    summaries = [
        StoryReactionSummary(emoji=emoji, count=int(count))
        for emoji, count in rows
        if emoji
    ]
    summaries.sort(key=lambda item: (-item.count, item.emoji))
    my_reaction = None
    if viewer_id is not None:
        mine = (
            db.query(StoryReaction)
            .filter(
                StoryReaction.story_id == story_id,
                StoryReaction.user_id == viewer_id,
            )
            .first()
        )
        if mine:
            my_reaction = mine.emoji
    return summaries, my_reaction


def _to_response(
    story: Story,
    db: Session,
    *,
    viewer_id: Optional[int] = None,
) -> StoryResponse:
    user = story.user
    reactions, my_reaction = _reaction_summaries(db, story.id, viewer_id)
    return StoryResponse(
        id=story.id,
        user_id=story.user_id,
        media_url=story.media_url,
        thumbnail_url=story.thumbnail_url,
        media_type=story.media_type,
        caption=story.caption,
        visibility=story.visibility,
        views_count=story.views_count or 0,
        created_at=story.created_at.isoformat(),
        expires_at=story.expires_at.isoformat(),
        author=_author_response(user),
        reactions=reactions,
        my_reaction=my_reaction,
    )


def _recount_views(db: Session, story: Story) -> None:
    count = (
        db.query(func.count(StoryView.id))
        .filter(StoryView.story_id == story.id)
        .scalar()
    )
    story.views_count = int(count or 0)


def _following_ids(db: Session, user_id: int) -> list[int]:
    rows = (
        db.query(Follower.followee_id)
        .filter(Follower.follower_id == user_id)
        .all()
    )
    return [int(row[0]) for row in rows]


def _close_friend_owner_ids(db: Session, viewer_id: int) -> list[int]:
    """Owners who listed viewer as a close friend."""
    rows = (
        db.query(CloseFriend.user_id)
        .filter(CloseFriend.friend_user_id == viewer_id)
        .all()
    )
    return [int(row[0]) for row in rows]


def can_view_story(story: Story, viewer: User, db: Session) -> bool:
    """Telegram-like story privacy: public / followers / close_friends / private."""
    if story.user_id == viewer.id:
        return True
    visibility = (story.visibility or "public").strip().lower()
    if visibility == "public":
        return True
    if visibility == "private":
        return False
    if visibility == "followers":
        row = (
            db.query(Follower.id)
            .filter(
                Follower.follower_id == viewer.id,
                Follower.followee_id == story.user_id,
            )
            .first()
        )
        return row is not None
    if visibility == "close_friends":
        row = (
            db.query(CloseFriend.id)
            .filter(
                CloseFriend.user_id == story.user_id,
                CloseFriend.friend_user_id == viewer.id,
            )
            .first()
        )
        return row is not None
    return False


def _ensure_can_view(story: Story, viewer: User, db: Session) -> None:
    if not can_view_story(story, viewer, db):
        raise HTTPException(status_code=404, detail="Story not found")


@router.get("", response_model=List[StoryResponse])
async def list_active_stories(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
    limit: int = 100,
):
    """Активные сторис, видимые текущему пользователю (privacy-aware)."""
    limit = min(max(limit, 1), 200)
    following = _following_ids(db, current_user.id)
    close_owners = _close_friend_owner_ids(db, current_user.id)
    visibility_filter = or_(
        Story.user_id == current_user.id,
        Story.visibility == "public",
        and_(
            Story.visibility == "followers",
            Story.user_id.in_(following if following else [-1]),
        ),
        and_(
            Story.visibility == "close_friends",
            Story.user_id.in_(close_owners if close_owners else [-1]),
        ),
    )
    stories = (
        _active_story_query(db)
        .filter(visibility_filter)
        .order_by(Story.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_to_response(story, db, viewer_id=current_user.id) for story in stories]


@router.get("/mine", response_model=List[StoryResponse])
async def list_my_stories(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    stories = (
        _active_story_query(db)
        .filter(Story.user_id == current_user.id)
        .order_by(Story.created_at.desc())
        .all()
    )
    return [_to_response(story, db, viewer_id=current_user.id) for story in stories]


@router.post("", response_model=StoryResponse, status_code=status.HTTP_201_CREATED)
async def create_story(
    payload: StoryCreateRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Создать сторис. Срок жизни — 24 часа."""
    visibility = (payload.visibility or "public").strip().lower()
    if visibility not in _VALID_VISIBILITY:
        raise HTTPException(status_code=400, detail="Invalid visibility")
    if visibility == "close_friends":
        from app.services.subscription_service import SubscriptionService

        SubscriptionService(db).require_feature(
            current_user.id,
            "story_close_friends",
            "Сторис для близких доступны с уровня 20",
        )
    story = Story(
        user_id=current_user.id,
        media_url=payload.media_url,
        thumbnail_url=payload.thumbnail_url,
        media_type=payload.media_type,
        caption=payload.caption,
        visibility=visibility,
        expires_at=datetime.utcnow() + timedelta(hours=24),
    )
    db.add(story)
    db.commit()
    db.refresh(story)
    story.user = current_user
    return _to_response(story, db, viewer_id=current_user.id)


@router.post("/{story_id}/view", response_model=StoryResponse)
async def mark_story_viewed(
    story_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    story = _active_story_query(db).filter(Story.id == story_id).first()
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    _ensure_can_view(story, current_user, db)
    if story.user_id != current_user.id:
        existing = (
            db.query(StoryView)
            .filter(
                StoryView.story_id == story.id,
                StoryView.user_id == current_user.id,
            )
            .first()
        )
        if existing is None:
            db.add(
                StoryView(
                    story_id=story.id,
                    user_id=current_user.id,
                )
            )
            db.flush()
            _recount_views(db, story)
            db.commit()
            db.refresh(story)
        else:
            existing.viewed_at = datetime.utcnow()
            db.commit()
    return _to_response(story, db, viewer_id=current_user.id)


@router.get("/{story_id}/viewers", response_model=StoryViewersResponse)
async def list_story_viewers(
    story_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
    limit: int = 100,
):
    story = (
        db.query(Story)
        .filter(
            Story.id == story_id,
            Story.deleted_at.is_(None),
        )
        .first()
    )
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    if story.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the author can see viewers")
    from app.services.subscription_service import SubscriptionService

    SubscriptionService(db).require_feature(
        current_user.id,
        "story_viewers",
        "Список просмотров сторис доступен с уровня 19",
    )

    limit = min(max(limit, 1), 200)
    views = (
        db.query(StoryView)
        .options(joinedload(StoryView.user))
        .filter(StoryView.story_id == story.id)
        .order_by(StoryView.viewed_at.desc())
        .limit(limit)
        .all()
    )
    reaction_by_user = {
        row.user_id: row.emoji
        for row in db.query(StoryReaction)
        .filter(StoryReaction.story_id == story.id)
        .all()
    }
    items = [
        StoryViewerItem(
            user=_author_response(view.user),
            viewed_at=view.viewed_at.isoformat(),
            reaction=reaction_by_user.get(view.user_id),
        )
        for view in views
        if view.user is not None
    ]
    return StoryViewersResponse(
        views_count=int(story.views_count or 0),
        items=items,
    )


@router.post("/{story_id}/reactions", response_model=StoryResponse)
async def set_story_reaction(
    story_id: int,
    payload: StoryReactionRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    story = _active_story_query(db).filter(Story.id == story_id).first()
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    _ensure_can_view(story, current_user, db)
    if story.user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot react to your own story")

    emoji = (payload.emoji or "").strip()
    if not emoji or len(emoji) > 16:
        raise HTTPException(status_code=400, detail="Invalid emoji")

    existing = (
        db.query(StoryReaction)
        .filter(
            StoryReaction.story_id == story.id,
            StoryReaction.user_id == current_user.id,
        )
        .first()
    )
    if existing:
        if existing.emoji == emoji:
            db.delete(existing)
        else:
            existing.emoji = emoji
    else:
        db.add(
            StoryReaction(
                story_id=story.id,
                user_id=current_user.id,
                emoji=emoji,
            )
        )
    db.commit()
    db.refresh(story)
    return _to_response(story, db, viewer_id=current_user.id)


@router.delete("/{story_id}/reactions", response_model=StoryResponse)
async def clear_story_reaction(
    story_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    story = _active_story_query(db).filter(Story.id == story_id).first()
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    _ensure_can_view(story, current_user, db)
    row = (
        db.query(StoryReaction)
        .filter(
            StoryReaction.story_id == story.id,
            StoryReaction.user_id == current_user.id,
        )
        .first()
    )
    if row:
        db.delete(row)
        db.commit()
        db.refresh(story)
    return _to_response(story, db, viewer_id=current_user.id)


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_story(
    story_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    story = (
        db.query(Story)
        .filter(
            and_(
                Story.id == story_id,
                Story.user_id == current_user.id,
                Story.deleted_at.is_(None),
            )
        )
        .first()
    )
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    story.deleted_at = datetime.utcnow()
    story.is_active = False
    db.commit()
    return None
