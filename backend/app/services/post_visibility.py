"""Who may see a post: public / followers / private."""
from __future__ import annotations

from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy.sql import exists

from app.models.follower import Follower
from app.models.post import Post
from app.models.user import User


def viewer_follows(db: Session, *, viewer_id: int, author_id: int) -> bool:
    if viewer_id == author_id:
        return True
    return (
        db.query(Follower.id)
        .filter(
            Follower.follower_id == viewer_id,
            Follower.followee_id == author_id,
        )
        .first()
        is not None
    )


def profile_locked_for_viewer(
    db: Session,
    user: User,
    viewer: Optional[User],
) -> bool:
    """Private account: strangers get a locked card, not a 403."""
    if not getattr(user, "is_private", False):
        return False
    if viewer is not None and viewer.id == user.id:
        return False
    if viewer is None or db is None:
        return True
    return not viewer_follows(db, viewer_id=viewer.id, author_id=user.id)


def can_view_post(
    db: Session,
    post: Post,
    viewer: Optional[User],
) -> bool:
    return can_view_post_fields(
        db,
        visibility=getattr(post, "visibility", None),
        author_id=getattr(post, "user_id", None),
        viewer=viewer,
    )


def can_view_post_fields(
    db: Session,
    *,
    visibility: Optional[str],
    author_id: Optional[int],
    viewer: Optional[User],
) -> bool:
    vis = (visibility or "public").strip().lower()
    if vis == "public":
        return True
    if author_id is None:
        return False
    if viewer is not None and viewer.id == author_id:
        return True
    if vis == "private":
        return False
    if vis == "followers":
        if viewer is None:
            return False
        return viewer_follows(db, viewer_id=viewer.id, author_id=author_id)
    return False


def require_can_view_post(
    db: Session,
    post: Post,
    viewer: Optional[User],
) -> None:
    if can_view_post(db, post, viewer):
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Пост закрытый",
    )


def search_visibility_clause(user_id: Optional[int]):
    """SQL filter for search/list: public, own, or followers-only if following."""
    from sqlalchemy import and_, or_

    if user_id is None:
        return Post.visibility == "public"
    follow_exists = exists().where(
        Follower.follower_id == user_id,
        Follower.followee_id == Post.user_id,
    )
    return or_(
        Post.visibility == "public",
        Post.user_id == user_id,
        and_(Post.visibility == "followers", follow_exists),
    )
