"""GIF catalog API (Tenor proxy)."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.schemas.gif import GifSearchResponse
from app.services import gif_search_service
from app.services.subscription_service import SubscriptionService

router = APIRouter()


def _require_gif_search(db: Session, user: User) -> None:
    SubscriptionService(db).require_feature(
        user.id,
        "gif_search",
        "Поиск GIF доступен с уровня 21",
    )


@router.get("/gifs/search", response_model=GifSearchResponse)
async def search_gifs(
    q: str = Query("", max_length=64),
    limit: int = Query(24, ge=1, le=50),
    pos: str | None = Query(None, max_length=128),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    _require_gif_search(db, current_user)
    try:
        return await gif_search_service.search_gifs(query=q, limit=limit, pos=pos)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="GIF search unavailable",
        ) from exc


@router.get("/gifs/featured", response_model=GifSearchResponse)
async def featured_gifs(
    limit: int = Query(24, ge=1, le=50),
    pos: str | None = Query(None, max_length=128),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    _require_gif_search(db, current_user)
    try:
        return await gif_search_service.featured_gifs(limit=limit, pos=pos)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="GIF catalog unavailable",
        ) from exc
