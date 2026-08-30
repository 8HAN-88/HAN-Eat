"""Реакции на постах: сводка и запись."""
from __future__ import annotations

from collections import defaultdict
from typing import Dict, Iterable, List, Optional

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.entitlements import (
    EXCLUSIVE_REACTION_EMOJIS,
    HAN_PLUS_REQUIRED_CODE,
    STANDARD_POST_REACTION_EMOJIS,
)
from app.models.post import Post
from app.models.post_reaction import PostReaction
from app.services.subscription_service import SubscriptionService

ALLOWED_POST_REACTION_EMOJIS = frozenset(STANDARD_POST_REACTION_EMOJIS) | EXCLUSIVE_REACTION_EMOJIS


def summarize_post_reactions(
    db: Session,
    post_ids: Iterable[int],
    user_id: Optional[int],
) -> Dict[int, List[dict]]:
    ids = [int(pid) for pid in post_ids]
    if not ids:
        return {}
    rows = (
        db.query(PostReaction.post_id, PostReaction.emoji, func.count(PostReaction.id))
        .filter(PostReaction.post_id.in_(ids))
        .group_by(PostReaction.post_id, PostReaction.emoji)
        .all()
    )
    mine: Dict[int, set[str]] = defaultdict(set)
    if user_id:
        mine_rows = (
            db.query(PostReaction.post_id, PostReaction.emoji)
            .filter(PostReaction.post_id.in_(ids), PostReaction.user_id == user_id)
            .all()
        )
        for pid, emoji in mine_rows:
            mine[int(pid)].add(str(emoji))
    out: Dict[int, List[dict]] = {pid: [] for pid in ids}
    for pid, emoji, cnt in rows:
        out.setdefault(int(pid), []).append(
            {
                "emoji": str(emoji),
                "count": int(cnt),
                "reacted_by_me": str(emoji) in mine.get(int(pid), set()),
            }
        )
    for pid in out:
        out[pid].sort(key=lambda item: (-int(item["count"]), item["emoji"]))
    return out


def set_post_reaction(db: Session, *, post_id: int, user_id: int, emoji: str) -> List[dict]:
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.deleted_at.is_(None))
        .first()
    )
    if not post:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Post not found")
    clean = (emoji or "").strip()
    if clean not in ALLOWED_POST_REACTION_EMOJIS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="unsupported_emoji")
    if clean in EXCLUSIVE_REACTION_EMOJIS and not SubscriptionService(db).has_entitlement(
        user_id, "exclusive_reactions"
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_PLUS_REQUIRED_CODE,
                "message": "Эксклюзивные реакции доступны по подписке",
            },
        )
    row = (
        db.query(PostReaction)
        .filter(PostReaction.post_id == post_id, PostReaction.user_id == user_id)
        .first()
    )
    if row and row.emoji == clean:
        db.delete(row)
    elif row:
        row.emoji = clean
    else:
        db.add(PostReaction(post_id=post_id, user_id=user_id, emoji=clean))
    db.flush()
    return summarize_post_reactions(db, [post_id], user_id).get(post_id, [])
