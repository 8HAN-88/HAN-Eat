"""
API endpoints для модерации (очередь, approve/reject, warn/ban).
"""
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.dependencies import (
    get_current_admin_required,
    get_current_moderator_required,
)
from app.core.database import get_db
from app.models.comment import Comment
from app.models.moderation_queue import ModerationQueue
from app.models.post import Post
from app.models.user import User
from app.services.content_report_service import ContentReportService
from app.services.moderation_audit_service import ModerationAuditService
from app.services.trust_score_service import TrustScoreService
from app.models.moderation_audit_log import ModerationAuditLog
from app.models.content_report import ContentReport
from app.services.analytics_service import AnalyticsService
from app.services.notification_service import NotificationService

router = APIRouter()


def _log_moderation_action(
    db: Session,
    *,
    event_type: str,
    entity_type: str,
    entity_id: int,
    moderator_id: int,
    author_id: Optional[int] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> None:
    AnalyticsService(db).log_event(
        event_type=event_type,
        entity_type=entity_type,
        entity_id=entity_id,
        user_id=moderator_id,
        author_id=author_id,
        metadata=metadata or {},
    )


class ApproveRequest(BaseModel):
    comment: Optional[str] = None


class RejectRequest(BaseModel):
    reason: str  # spam | inappropriate | copyright | harassment | other
    comment: Optional[str] = None


class WarnUserRequest(BaseModel):
    message: Optional[str] = None


class BanUserRequest(BaseModel):
    reason: Optional[str] = None


def _enrich_item(db: Session, item: ModerationQueue) -> Dict[str, Any]:
    content_data = None
    user_data = None

    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            author = db.query(User).filter(User.id == post.user_id).first()
            content_data = {
                "id": post.id,
                "type": post.type,
                "title": post.title,
                "description": post.description,
                "status": post.status,
                "author": {
                    "id": author.id,
                    "name": author.name,
                    "username": author.username,
                }
                if author
                else None,
            }
    elif item.content_type == "comment":
        comment = db.query(Comment).filter(Comment.id == item.content_id).first()
        if comment:
            author = db.query(User).filter(User.id == comment.user_id).first()
            content_data = {
                "id": comment.id,
                "text": comment.text,
                "post_id": comment.post_id,
                "author": {
                    "id": author.id,
                    "name": author.name,
                    "username": author.username,
                }
                if author
                else None,
            }
    elif item.content_type == "channel":
        from app.models.community import Channel

        channel = db.query(Channel).filter(Channel.id == item.content_id).first()
        if channel:
            owner = db.query(User).filter(User.id == channel.admin_user_id).first()
            content_data = {
                "id": channel.id,
                "title": channel.name,
                "description": channel.description,
                "author": {
                    "id": owner.id,
                    "name": owner.name,
                    "username": owner.username,
                }
                if owner
                else None,
            }

    if item.user_id:
        user = db.query(User).filter(User.id == item.user_id).first()
        if user:
            user_data = {
                "id": user.id,
                "name": user.name,
                "username": user.username,
                "avatar_url": user.avatar_url,
                "trust_score": float(user.trust_score or 0.5),
            }

    flagged_by_user = None
    if item.flagged_by_user_id:
        flagger = db.query(User).filter(User.id == item.flagged_by_user_id).first()
        if flagger:
            flagged_by_user = {
                "id": flagger.id,
                "name": flagger.name,
                "username": flagger.username,
            }
        else:
            flagged_by_user = {
                "id": item.flagged_by_user_id,
                "name": f"Пользователь #{item.flagged_by_user_id}",
                "username": None,
            }

    report_svc = ContentReportService(db)
    reports_24h = report_svc.report_count(item.content_type, item.content_id, hours=24)
    recent_reports = report_svc.list_recent_reports(
        item.content_type, item.content_id, limit=10
    )

    return {
        "id": item.id,
        "content_type": item.content_type,
        "content_id": item.content_id,
        "content": content_data,
        "content_preview": content_data,
        "user": user_data,
        "user_id": item.user_id,
        "status": item.status,
        "reason": item.reason,
        "report_category": item.report_category,
        "flagged_by_user_id": item.flagged_by_user_id,
        "flagged_by": item.flagged_by_user_id,
        "flagged_by_user": flagged_by_user,
        "created_at": item.created_at.isoformat() if item.created_at else None,
        "toxicity_score": item.toxicity_score,
        "spam_score": item.spam_score,
        "nsfw_score": item.nsfw_score,
        "danger_score": item.danger_score,
        "ai_decision": item.ai_decision,
        "reports_count_24h": reports_24h,
        "recent_reports": recent_reports,
        "report_comment": item.moderation_comment
        if item.reason == "reported"
        else None,
    }


@router.get("/content-reports")
async def get_content_reports(
    content_type: str = Query(...),
    content_id: int = Query(..., ge=1),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_moderator_required),
):
    """Жалобы на конкретный пост/комментарий/канал (для очереди модерации)."""
    report_svc = ContentReportService(db)
    return {
        "reports": report_svc.list_recent_reports(
            content_type, content_id, limit=20
        )
    }


@router.get("/pending")
async def get_pending_moderation(
    content_type: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_moderator_required),
):
    """Очередь модерации."""
    query = db.query(ModerationQueue).filter(ModerationQueue.status == "pending")
    if content_type and content_type not in ("all", "user_profile"):
        query = query.filter(ModerationQueue.content_type == content_type)

    items = (
        query.order_by(ModerationQueue.created_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    enriched = [_enrich_item(db, item) for item in items]
    total = (
        db.query(func.count(ModerationQueue.id))
        .filter(ModerationQueue.status == "pending")
        .scalar()
        or 0
    )
    has_more = offset + len(items) < total
    return {
        "items": enriched,
        "total": total,
        "offset": offset,
        "limit": limit,
        "has_more": has_more,
        "next_cursor": str(offset + limit) if has_more else None,
    }


@router.get("/stats")
async def moderation_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_moderator_required),
):
    """Краткая аналитика для панели модератора."""
    pending = (
        db.query(func.count(ModerationQueue.id))
        .filter(ModerationQueue.status == "pending")
        .scalar()
        or 0
    )
    since = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    moderated_today = (
        db.query(func.count(ModerationQueue.id))
        .filter(
            ModerationQueue.status.in_(["approved", "rejected"]),
            ModerationQueue.moderated_at >= since,
        )
        .scalar()
        or 0
    )
    reports_7d = (
        db.query(func.count(ContentReport.id))
        .filter(ContentReport.created_at >= datetime.utcnow() - timedelta(days=7))
        .scalar()
        or 0
    )
    return {
        "pending": pending,
        "moderated_today": moderated_today,
        "reports_last_7d": reports_7d,
    }


@router.get("/dashboard")
async def moderation_dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_moderator_required),
):
    """Панель модератора: сводка для admin UI."""
    since = datetime.utcnow() - timedelta(days=7)
    pending = (
        db.query(func.count(ModerationQueue.id))
        .filter(ModerationQueue.status == "pending")
        .scalar()
        or 0
    )
    auto_flagged = (
        db.query(func.count(ModerationQueue.id))
        .filter(
            ModerationQueue.status == "pending",
            ModerationQueue.reason == "auto_flagged",
        )
        .scalar()
        or 0
    )
    reported = (
        db.query(func.count(ModerationQueue.id))
        .filter(
            ModerationQueue.status == "pending",
            ModerationQueue.reason == "reported",
        )
        .scalar()
        or 0
    )
    reports_week = (
        db.query(func.count(ContentReport.id))
        .filter(ContentReport.created_at >= since)
        .scalar()
        or 0
    )
    banned_users = (
        db.query(func.count(User.id)).filter(User.banned_at.isnot(None)).scalar() or 0
    )
    shadow_users = (
        db.query(func.count(User.id))
        .filter(User.shadow_moderation == True, User.banned_at.is_(None))
        .scalar()
        or 0
    )
    recent_audit = (
        db.query(ModerationAuditLog)
        .order_by(ModerationAuditLog.created_at.desc())
        .limit(15)
        .all()
    )
    return {
        "pending_total": pending,
        "pending_auto_flagged": auto_flagged,
        "pending_reported": reported,
        "reports_last_7d": reports_week,
        "banned_users": banned_users,
        "shadow_users": shadow_users,
        "recent_actions": [
            {
                "id": a.id,
                "action": a.action,
                "content_type": a.content_type,
                "content_id": a.content_id,
                "target_user_id": a.target_user_id,
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in recent_audit
        ],
    }


@router.post("/users/{user_id}/shadow")
async def set_shadow_moderation(
    user_id: int,
    enabled: bool = Query(...),
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    target.shadow_moderation = enabled
    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="shadow_on" if enabled else "shadow_off",
        target_user_id=user_id,
    )
    db.commit()
    return {"shadow_moderation": enabled}


@router.post("/{item_id}/approve")
async def approve_content(
    item_id: int,
    request: ApproveRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    item = db.query(ModerationQueue).filter(ModerationQueue.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Moderation item not found")
    if item.status != "pending":
        raise HTTPException(status_code=400, detail="Item already moderated")

    author_id = None
    content_label = "Контент"
    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            author_id = post.user_id
            content_label = "Рилс" if post.type == "reel" else "Пост"
            post.status = "published"
            post.hidden_from_recommendations = False
            if not post.published_at:
                post.published_at = datetime.utcnow()
    elif item.content_type == "comment":
        comment = db.query(Comment).filter(Comment.id == item.content_id).first()
        if comment:
            author_id = comment.user_id
            content_label = "Комментарий"
            comment.deleted_at = None

    item.status = "approved"
    item.moderated_by_user_id = current_user.id
    item.moderation_comment = request.comment
    item.moderated_at = datetime.utcnow()

    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="approve",
        content_type=item.content_type,
        content_id=item.content_id,
        target_user_id=author_id,
    )
    if author_id:
        TrustScoreService(db).on_content_approved(author_id)

    if author_id:
        NotificationService(db).create_notification(
            user_id=author_id,
            type="moderation_approved",
            title="Модерация пройдена",
            body=f"Ваш {content_label} одобрен и опубликован.",
            entity_type=item.content_type,
            entity_id=item.content_id,
            actor_id=current_user.id,
            data={"action": "approved"},
        )

    _log_moderation_action(
        db,
        event_type="moderation_approve",
        entity_type=item.content_type,
        entity_id=item.content_id,
        moderator_id=current_user.id,
        author_id=author_id,
    )
    db.commit()
    return {"approved": True, "content_type": item.content_type, "content_id": item.content_id}


@router.post("/{item_id}/reject")
async def reject_content(
    item_id: int,
    request: RejectRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    item = db.query(ModerationQueue).filter(ModerationQueue.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Moderation item not found")
    if item.status != "pending":
        raise HTTPException(status_code=400, detail="Item already moderated")

    author_id = None
    content_label = "Контент"
    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            author_id = post.user_id
            content_label = "Рилс" if post.type == "reel" else "Пост"
            post.status = "rejected"
            post.hidden_from_recommendations = True
    elif item.content_type == "comment":
        comment = db.query(Comment).filter(Comment.id == item.content_id).first()
        if comment:
            author_id = comment.user_id
            content_label = "Комментарий"
            comment.deleted_at = datetime.utcnow()

    item.status = "rejected"
    item.moderated_by_user_id = current_user.id
    item.rejection_reason = request.reason
    item.moderation_comment = request.comment
    item.moderated_at = datetime.utcnow()

    if author_id:
        TrustScoreService(db).on_content_rejected(author_id)

    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="reject",
        content_type=item.content_type,
        content_id=item.content_id,
        target_user_id=author_id,
        details={"reason": request.reason},
    )

    if author_id:
        reason_text = request.reason
        NotificationService(db).create_notification(
            user_id=author_id,
            type="moderation_rejected",
            title="Модерация не пройдена",
            body=f"Ваш {content_label} отклонён. Причина: {reason_text}.",
            entity_type=item.content_type,
            entity_id=item.content_id,
            actor_id=current_user.id,
            data={"action": "rejected", "reason": request.reason},
        )

    _log_moderation_action(
        db,
        event_type="moderation_reject",
        entity_type=item.content_type,
        entity_id=item.content_id,
        moderator_id=current_user.id,
        author_id=author_id,
        metadata={"reason": request.reason},
    )
    db.commit()
    return {"rejected": True}


@router.post("/{item_id}/hide")
async def hide_content(
    item_id: int,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    """Скрыть из рекомендаций, оставить на профиле при published."""
    item = db.query(ModerationQueue).filter(ModerationQueue.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Not found")
    if item.content_type == "post":
        post = db.query(Post).filter(Post.id == item.content_id).first()
        if post:
            post.hidden_from_recommendations = True
    item.status = "approved"
    item.moderated_by_user_id = current_user.id
    item.moderated_at = datetime.utcnow()
    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="hide",
        content_type=item.content_type,
        content_id=item.content_id,
    )
    _log_moderation_action(
        db,
        event_type="moderation_hide",
        entity_type=item.content_type,
        entity_id=item.content_id,
        moderator_id=current_user.id,
    )
    db.commit()
    return {"hidden": True}


@router.post("/users/{user_id}/warn")
async def warn_user(
    user_id: int,
    request: WarnUserRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    target.account_warnings = (target.account_warnings or 0) + 1
    TrustScoreService(db).on_warning(user_id)
    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="warn_user",
        target_user_id=user_id,
        details={"message": request.message},
    )
    NotificationService(db).create_notification(
        user_id=user_id,
        type="moderation_warning",
        title="Предупреждение",
        body=request.message or "Ваш контент нарушает правила сообщества.",
        entity_type="user",
        entity_id=user_id,
        actor_id=current_user.id,
        data={},
    )
    _log_moderation_action(
        db,
        event_type="moderation_warn",
        entity_type="user",
        entity_id=user_id,
        moderator_id=current_user.id,
        author_id=user_id,
    )
    db.commit()
    return {"warned": True, "warnings": target.account_warnings}


@router.post("/users/{user_id}/ban")
async def ban_user(
    user_id: int,
    request: BanUserRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    if target.is_admin:
        raise HTTPException(status_code=400, detail="Cannot ban admin")
    target.banned_at = datetime.utcnow()
    target.trust_score = 0.0
    ModerationAuditService(db).log(
        moderator_user_id=current_user.id,
        action="ban_user",
        target_user_id=user_id,
        details={"reason": request.reason},
    )
    _log_moderation_action(
        db,
        event_type="moderation_ban",
        entity_type="user",
        entity_id=user_id,
        moderator_id=current_user.id,
        author_id=user_id,
        metadata={"reason": request.reason},
    )
    db.commit()
    return {"banned": True}
