"""Применение результата пайплайна к посту/комментарию."""
from datetime import datetime
from typing import List, Optional

from sqlalchemy.orm import Session

from app.models.moderation_queue import ModerationQueue
from app.models.post import Post
from app.models.user import User
from app.services.analytics_service import AnalyticsService
from app.services.moderation_pipeline_service import (
    DECISION_BLOCK,
    DECISION_SAFE,
    DECISION_WARNING,
    ModerationPipelineService,
    ModerationScores,
)


def _log_ai_moderation(
    db: Session,
    *,
    entity_type: str,
    entity_id: int,
    author_id: int,
    decision: str,
    scores: ModerationScores,
) -> None:
    event_type = (
        "ai_moderation_block"
        if decision == DECISION_BLOCK
        else "ai_moderation_warning"
        if decision == DECISION_WARNING
        else "ai_moderation_safe"
    )
    AnalyticsService(db).log_event(
        event_type=event_type,
        entity_type=entity_type,
        entity_id=entity_id,
        author_id=author_id,
        metadata={
            "decision": decision,
            "toxicity": scores.toxicity_score,
            "spam": scores.spam_score,
            "nsfw": scores.nsfw_score,
            "danger": scores.danger_score,
        },
    )


def _collect_post_image_urls(post: Post) -> List[str]:
    urls: List[str] = []
    body = post.body if isinstance(post.body, dict) else {}
    for key in ("image_url", "thumbnail_url", "cover_url", "media_url"):
        u = body.get(key)
        if isinstance(u, str) and u.startswith("http"):
            urls.append(u)
    media = body.get("media")
    if isinstance(media, list):
        for m in media:
            if isinstance(m, dict):
                u = m.get("url") or m.get("image_url")
                if isinstance(u, str) and u.startswith("http"):
                    urls.append(u)
    return urls


def raise_if_post_rejected(db: Session, post: Post, scores: ModerationScores) -> None:
    """Откат транзакции и 400 CONTENT_BLOCKED, если пост отклонён AI."""
    if post.status != "rejected":
        return
    from fastapi import HTTPException, status

    db.rollback()
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail={
            "code": "CONTENT_BLOCKED",
            "message": "Публикация не прошла модерацию и не может быть опубликована",
            "ai_decision": scores.decision,
        },
    )


def run_post_moderation(
    db: Session,
    post: Post,
    author: User,
    *,
    force_pipeline: bool = True,
) -> ModerationScores:
    """
    Запускает AI pipeline и применяет статус поста.
    Возвращает scores для записи в очередь.
    """
    from app.core.config import settings

    pipeline_enabled = getattr(settings, "ENABLE_AI_MODERATION", True)
    if not force_pipeline or not pipeline_enabled:
        post.status = "published"
        post.published_at = datetime.utcnow()
        return ModerationScores(decision=DECISION_SAFE)

    if author.is_admin or author.is_moderator:
        post.status = "published"
        post.published_at = datetime.utcnow()
        return ModerationScores(decision=DECISION_SAFE)

    svc = ModerationPipelineService()
    scores = svc.analyze_text(
        text=post.description or "",
        title=post.title,
        image_urls=_collect_post_image_urls(post),
        trust_score=float(author.trust_score or 0.5),
    )

    if scores.decision == DECISION_BLOCK:
        post.status = "rejected"
        post.hidden_from_recommendations = True
        _log_ai_moderation(
            db,
            entity_type="post",
            entity_id=post.id,
            author_id=author.id,
            decision=scores.decision,
            scores=scores,
        )
    elif scores.decision == DECISION_WARNING:
        post.status = "pending"
        post.hidden_from_recommendations = True
        _enqueue(db, post, author.id, scores)
        _log_ai_moderation(
            db,
            entity_type="post",
            entity_id=post.id,
            author_id=author.id,
            decision=scores.decision,
            scores=scores,
        )
    else:
        post.status = "published"
        post.published_at = datetime.utcnow()
        post.hidden_from_recommendations = False

    return scores


def run_comment_moderation(
    db: Session,
    comment_id: int,
    text: str,
    author: User,
) -> ModerationScores:
    from app.core.config import settings

    if not getattr(settings, "ENABLE_AI_MODERATION", True):
        return ModerationScores(decision=DECISION_SAFE)

    if author.is_admin or author.is_moderator:
        return ModerationScores(decision=DECISION_SAFE)

    svc = ModerationPipelineService()
    scores = svc.analyze_text(
        text=text,
        trust_score=float(author.trust_score or 0.5),
    )

    if scores.decision == DECISION_BLOCK:
        from app.models.comment import Comment

        c = db.query(Comment).filter(Comment.id == comment_id).first()
        if c:
            c.deleted_at = datetime.utcnow()
        _log_ai_moderation(
            db,
            entity_type="comment",
            entity_id=comment_id,
            author_id=author.id,
            decision=scores.decision,
            scores=scores,
        )
    elif scores.decision == DECISION_WARNING:
        item = ModerationQueue(
            content_type="comment",
            content_id=comment_id,
            user_id=author.id,
            status="pending",
            reason="auto_flagged",
            toxicity_score=scores.toxicity_score,
            spam_score=scores.spam_score,
            nsfw_score=scores.nsfw_score,
            danger_score=scores.danger_score,
            ai_decision=scores.decision,
        )
        db.add(item)
        _log_ai_moderation(
            db,
            entity_type="comment",
            entity_id=comment_id,
            author_id=author.id,
            decision=scores.decision,
            scores=scores,
        )

    return scores


def _enqueue(db: Session, post: Post, author_id: int, scores: ModerationScores) -> None:
    existing = (
        db.query(ModerationQueue)
        .filter(
            ModerationQueue.content_type == "post",
            ModerationQueue.content_id == post.id,
            ModerationQueue.status == "pending",
        )
        .first()
    )
    if existing:
        existing.toxicity_score = scores.toxicity_score
        existing.spam_score = scores.spam_score
        existing.nsfw_score = scores.nsfw_score
        existing.danger_score = scores.danger_score
        existing.ai_decision = scores.decision
        return

    db.add(
        ModerationQueue(
            content_type="post",
            content_id=post.id,
            user_id=author_id,
            status="pending",
            reason="auto_flagged",
            toxicity_score=scores.toxicity_score,
            spam_score=scores.spam_score,
            nsfw_score=scores.nsfw_score,
            danger_score=scores.danger_score,
            ai_decision=scores.decision,
        )
    )
