"""
API для Stories / Моментов.
"""
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.story import Story
from app.models.user import User

router = APIRouter(prefix="/stories", tags=["Stories"])


class StoryCreateRequest(BaseModel):
    media_url: str = Field(..., min_length=1, max_length=2000)
    thumbnail_url: Optional[str] = Field(None, max_length=2000)
    media_type: str = Field(..., pattern="^(image|video)$")
    caption: Optional[str] = Field(None, max_length=500)
    visibility: str = Field("public", pattern="^(public|followers|private)$")


class StoryAuthorResponse(BaseModel):
    id: int
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None


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


def _active_story_query(db: Session):
    now = datetime.utcnow()
    return (
        db.query(Story)
        .options(joinedload(Story.user))
        .filter(
            Story.deleted_at.is_(None),
            Story.is_active == True,
            Story.expires_at > now,
        )
    )


def _to_response(story: Story) -> StoryResponse:
    user = story.user
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
        author=StoryAuthorResponse(
            id=user.id,
            name=user.name,
            username=user.username,
            avatar_url=user.avatar_url,
        ),
    )


@router.get("", response_model=List[StoryResponse])
async def list_active_stories(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
    limit: int = 100,
):
    """Активные сторис за последние 24 часа."""
    limit = min(max(limit, 1), 200)
    stories = (
        _active_story_query(db)
        .filter(Story.visibility == "public")
        .order_by(Story.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_to_response(story) for story in stories]


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
    return [_to_response(story) for story in stories]


@router.post("", response_model=StoryResponse, status_code=status.HTTP_201_CREATED)
async def create_story(
    payload: StoryCreateRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Создать сторис. Срок жизни — 24 часа."""
    story = Story(
        user_id=current_user.id,
        media_url=payload.media_url,
        thumbnail_url=payload.thumbnail_url,
        media_type=payload.media_type,
        caption=payload.caption,
        visibility=payload.visibility,
        expires_at=datetime.utcnow() + timedelta(hours=24),
    )
    db.add(story)
    db.commit()
    db.refresh(story)
    story.user = current_user
    return _to_response(story)


@router.post("/{story_id}/view", response_model=StoryResponse)
async def mark_story_viewed(
    story_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    story = _active_story_query(db).filter(Story.id == story_id).first()
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    if story.user_id != current_user.id:
        story.views_count = int(story.views_count or 0) + 1
        db.commit()
        db.refresh(story)
    return _to_response(story)


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
