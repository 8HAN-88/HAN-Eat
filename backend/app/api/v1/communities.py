"""
Legacy API: «сообщество» = канал (channels). Используйте /api/v1/channels/{id}.
"""
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.api.v1.channels import get_channel
from app.core.database import get_db
from app.models.user import User
from app.schemas.channel import ChannelDetailResponse

router = APIRouter()


@router.get("/{community_id}", response_model=ChannelDetailResponse)
async def get_community(
    community_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user),
):
    """Получить канал по id (ранее community_id)."""
    return await get_channel(
        channel_id=community_id,
        db=db,
        current_user=current_user,
    )
