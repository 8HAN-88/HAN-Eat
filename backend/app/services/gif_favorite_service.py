"""Cloud GIF favorites."""

from __future__ import annotations

from typing import List

from sqlalchemy.orm import Session

from app.models.gif_favorite import GifFavorite

MAX_GIF_FAVORITES = 80


class GifFavoriteError(ValueError):
    pass


def list_favorites(db: Session, user_id: int) -> List[GifFavorite]:
    return (
        db.query(GifFavorite)
        .filter(GifFavorite.user_id == user_id)
        .order_by(GifFavorite.created_at.desc(), GifFavorite.id.desc())
        .all()
    )


def toggle_favorite(
    db: Session,
    user_id: int,
    media_url: str,
    preview_url: str | None = None,
    title: str | None = None,
) -> tuple[GifFavorite | None, bool]:
    url = (media_url or "").strip()
    if not url:
        raise GifFavoriteError("media_url_required")
    url = url[:1024]
    row = (
        db.query(GifFavorite)
        .filter(GifFavorite.user_id == user_id, GifFavorite.media_url == url)
        .first()
    )
    if row:
        db.delete(row)
        db.flush()
        return None, False
    count = db.query(GifFavorite).filter(GifFavorite.user_id == user_id).count()
    if count >= MAX_GIF_FAVORITES:
        raise GifFavoriteError("gif_favorite_limit")
    row = GifFavorite(
        user_id=user_id,
        media_url=url,
        preview_url=(preview_url or url)[:1024] if preview_url or url else None,
        title=(title or "").strip()[:80] or None,
    )
    db.add(row)
    db.flush()
    return row, True
