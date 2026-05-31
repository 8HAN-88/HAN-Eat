"""Опросы в постах: создание body и подсчёт голосов."""
from __future__ import annotations

import copy
from typing import Any, Dict, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.post_poll_vote import PostPollVote


def build_poll_body(question: str, option_texts: List[str]) -> Dict[str, Any]:
    q = (question or "").strip()
    opts = [t.strip() for t in option_texts if t and t.strip()]
    if len(q) < 1:
        raise ValueError("Poll question is required")
    if len(opts) < 2:
        raise ValueError("Poll must have at least 2 options")
    if len(opts) > 10:
        raise ValueError("Poll cannot have more than 10 options")
    return {
        "poll": {
            "question": q,
            "options": [{"index": i, "text": text} for i, text in enumerate(opts)],
            "is_closed": False,
        }
    }


def _vote_counts(db: Session, post_ids: List[int]) -> Dict[int, Dict[int, int]]:
    if not post_ids:
        return {}
    rows = (
        db.query(PostPollVote.post_id, PostPollVote.option_index, func.count(PostPollVote.id))
        .filter(PostPollVote.post_id.in_(post_ids))
        .group_by(PostPollVote.post_id, PostPollVote.option_index)
        .all()
    )
    out: Dict[int, Dict[int, int]] = {}
    for post_id, option_index, cnt in rows:
        out.setdefault(post_id, {})[option_index] = int(cnt)
    return out


def _user_votes(db: Session, post_ids: List[int], user_id: Optional[int]) -> Dict[int, int]:
    if not post_ids or user_id is None:
        return {}
    rows = (
        db.query(PostPollVote.post_id, PostPollVote.option_index)
        .filter(
            PostPollVote.post_id.in_(post_ids),
            PostPollVote.user_id == user_id,
        )
        .all()
    )
    return {row.post_id: row.option_index for row in rows}


def enrich_body_poll(
    db: Session,
    post_id: int,
    body: Optional[Dict[str, Any]],
    viewer_user_id: Optional[int],
    vote_counts: Optional[Dict[int, int]] = None,
    voted_index: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    if not body or not isinstance(body, dict):
        return body
    raw = body.get("poll")
    if not raw or not isinstance(raw, dict):
        return body
    stored_opts = raw.get("options")
    if not isinstance(stored_opts, list):
        return body

    if vote_counts is None:
        vote_counts = _vote_counts(db, [post_id]).get(post_id, {})
    if voted_index is None and viewer_user_id is not None:
        voted_index = _user_votes(db, [post_id], viewer_user_id).get(post_id)

    total = sum(vote_counts.values())
    enriched_opts = []
    for item in stored_opts:
        if not isinstance(item, dict):
            continue
        idx = item.get("index")
        if idx is None:
            continue
        text = item.get("text") or ""
        votes = vote_counts.get(int(idx), 0)
        pct = (votes / total * 100.0) if total > 0 else 0.0
        enriched_opts.append(
            {
                "text": text,
                "votes": votes,
                "percentage": round(pct, 1),
                "index": int(idx),
            }
        )

    result = copy.deepcopy(body)
    poll_out: Dict[str, Any] = {
        "question": raw.get("question") or "",
        "options": enriched_opts,
        "is_closed": bool(raw.get("is_closed", False)),
    }
    if voted_index is not None:
        poll_out["voted_option_index"] = voted_index
    result["poll"] = poll_out
    return result


def enrich_posts_poll_batch(
    db: Session,
    posts: List[Any],
    viewer_user_id: Optional[int],
) -> Dict[int, Dict[str, Any]]:
    """post_id -> enriched body для постов с опросом."""
    poll_post_ids = [
        p.id for p in posts if getattr(p, "type", None) == "poll" or (p.body or {}).get("poll")
    ]
    if not poll_post_ids:
        return {}
    counts_by_post = _vote_counts(db, poll_post_ids)
    user_votes = _user_votes(db, poll_post_ids, viewer_user_id)
    out: Dict[int, Dict[str, Any]] = {}
    for p in posts:
        if p.id not in poll_post_ids:
            continue
        enriched = enrich_body_poll(
            db,
            p.id,
            p.body,
            viewer_user_id,
            vote_counts=counts_by_post.get(p.id, {}),
            voted_index=user_votes.get(p.id),
        )
        if enriched is not None:
            out[p.id] = enriched
    return out


def poll_total_votes(db: Session, post_id: int) -> int:
    row = (
        db.query(func.count(PostPollVote.id))
        .filter(PostPollVote.post_id == post_id)
        .scalar()
    )
    return int(row or 0)


def update_poll_in_post(
    db: Session,
    post: Any,
    question: str,
    option_texts: List[str],
) -> None:
    """Обновить вопрос/варианты только пока нет голосов и опрос открыт."""
    if getattr(post, "type", None) != "poll":
        raise ValueError("Not a poll post")
    body = post.body or {}
    raw = body.get("poll") or {}
    if not isinstance(raw, dict):
        raise ValueError("Invalid poll body")
    if bool(raw.get("is_closed", False)):
        raise ValueError("Опрос закрыт")
    if poll_total_votes(db, post.id) > 0:
        raise ValueError("Нельзя изменить опрос после первого голоса")

    new_poll = build_poll_body(question, option_texts)["poll"]
    new_poll["is_closed"] = bool(raw.get("is_closed", False))
    body["poll"] = new_poll
    post.body = body


def vote_on_poll(
    db: Session,
    post_id: int,
    user_id: int,
    option_index: int,
) -> Dict[str, Any]:
    from app.models.post import Post

    post = db.query(Post).filter(Post.id == post_id, Post.deleted_at.is_(None)).first()
    if not post:
        raise ValueError("Post not found")
    if post.type != "poll":
        raise ValueError("Not a poll post")
    body = post.body or {}
    raw = body.get("poll") or {}
    if bool(raw.get("is_closed", False)):
        raise ValueError("Poll is closed")
    stored = raw.get("options") or []
    valid_indices = {
        int(o["index"])
        for o in stored
        if isinstance(o, dict) and o.get("index") is not None
    }
    if option_index not in valid_indices:
        raise ValueError("Invalid option index")

    existing = (
        db.query(PostPollVote)
        .filter(PostPollVote.post_id == post_id, PostPollVote.user_id == user_id)
        .first()
    )
    if existing:
        existing.option_index = option_index
    else:
        db.add(
            PostPollVote(
                post_id=post_id,
                user_id=user_id,
                option_index=option_index,
            )
        )
    db.commit()
    enriched = enrich_body_poll(db, post_id, post.body, user_id)
    return enriched.get("poll") if enriched else {}
