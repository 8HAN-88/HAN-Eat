"""
API endpoints для модерации (очередь, approve/reject, warn/ban).
"""
from datetime import datetime, timedelta
import json
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import String, func, or_
from sqlalchemy.orm import Session

from app.api.dependencies import (
    get_current_admin_required,
    get_current_moderator_required,
)
from app.core.config import settings
from app.core.database import get_db
from app.models.analytics_event import AnalyticsEvent
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
from app.services.bot_webhook_queue_service import (
    clear_dead_letters,
    clear_webhook_queue,
    force_promote_delayed,
    requeue_dead_letters,
    reset_webhook_metrics,
    webhook_dead_letter_page,
    webhook_queue_stats,
)

router = APIRouter()


def _webhook_operations_page(
    db: Session,
    *,
    limit: int = 20,
    offset: int = 0,
    query: Optional[str] = None,
    event_type: Optional[str] = None,
) -> Dict[str, Any]:
    page_limit = max(1, min(int(limit), 100))
    page_offset = max(0, int(offset))
    base_query = db.query(AnalyticsEvent).filter(
        AnalyticsEvent.entity_type == "system",
        AnalyticsEvent.event_type.like("bot_webhook_%"),
    )
    if event_type:
        base_query = base_query.filter(AnalyticsEvent.event_type == event_type.strip())
    q = (query or "").strip()
    if q:
        like_q = f"%{q}%"
        matched_user_ids = [
            int(row[0])
            for row in (
                db.query(User.id)
                .filter(
                    or_(
                        User.name.ilike(like_q),
                        User.username.ilike(like_q),
                    )
                )
                .limit(200)
                .all()
            )
        ]
        base_query = base_query.filter(
            or_(
                AnalyticsEvent.event_type.ilike(like_q),
                AnalyticsEvent.event_metadata.cast(String).ilike(like_q),
                AnalyticsEvent.user_id.in_(matched_user_ids) if matched_user_ids else False,
            )
        )
    total = int(base_query.with_entities(func.count(AnalyticsEvent.id)).scalar() or 0)
    rows = (
        base_query
        .order_by(AnalyticsEvent.created_at.desc(), AnalyticsEvent.id.desc())
        .offset(page_offset)
        .limit(page_limit)
        .all()
    )
    user_ids = {int(r.user_id) for r in rows if r.user_id is not None}
    users = {}
    if user_ids:
        users = {
            u.id: u
            for u in db.query(User).filter(User.id.in_(list(user_ids))).all()
        }
    items: List[Dict[str, Any]] = []
    for r in rows:
        actor = users.get(int(r.user_id)) if r.user_id is not None else None
        items.append(
            {
                "id": int(r.id),
                "event_type": r.event_type,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "user_id": int(r.user_id) if r.user_id is not None else None,
                "actor_name": actor.name if actor else None,
                "actor_username": actor.username if actor else None,
                "metadata": r.event_metadata or {},
            }
        )
    has_more = page_offset + len(items) < total
    return {
        "items": items,
        "total": total,
        "offset": page_offset,
        "limit": page_limit,
        "has_more": has_more,
        "next_offset": page_offset + page_limit if has_more else None,
    }


def _build_webhook_alerts(
    db: Session,
    *,
    queue_stats: Dict[str, Any],
) -> Dict[str, Any]:
    now = datetime.utcnow()
    since_1h = now - timedelta(hours=1)
    since_24h = now - timedelta(hours=24)

    fails_1h = int(
        db.query(func.count(AnalyticsEvent.id))
        .filter(
            AnalyticsEvent.entity_type == "bot",
            AnalyticsEvent.event_type == "bot_webhook_delivery_fail",
            AnalyticsEvent.created_at >= since_1h,
        )
        .scalar()
        or 0
    )
    ok_1h = int(
        db.query(func.count(AnalyticsEvent.id))
        .filter(
            AnalyticsEvent.entity_type == "bot",
            AnalyticsEvent.event_type == "bot_webhook_delivery_ok",
            AnalyticsEvent.created_at >= since_1h,
        )
        .scalar()
        or 0
    )
    auto_disabled_24h = int(
        db.query(func.count(AnalyticsEvent.id))
        .filter(
            AnalyticsEvent.entity_type == "bot",
            AnalyticsEvent.event_type == "bot_webhook_auto_disabled",
            AnalyticsEvent.created_at >= since_24h,
        )
        .scalar()
        or 0
    )

    delivery_attempts_1h = ok_1h + fails_1h
    fail_rate_1h = (
        (fails_1h / delivery_attempts_1h * 100.0) if delivery_attempts_1h > 0 else 0.0
    )
    dead_depth = int(queue_stats.get("dead_depth") or 0)
    dropped_total = int(queue_stats.get("dropped_total") or 0)
    throttled_total = int(queue_stats.get("throttled_total") or 0)

    alerts: List[Dict[str, Any]] = []

    dead_depth_threshold = max(1, int(getattr(settings, "BOT_WEBHOOK_ALERT_DEAD_DEPTH", 20)))
    if dead_depth >= dead_depth_threshold:
        alerts.append(
            {
                "code": "dead_letter_backlog",
                "severity": "critical",
                "message": "Dead-letter backlog is high",
                "value": dead_depth,
                "threshold": dead_depth_threshold,
            }
        )

    auto_disabled_threshold = max(
        1, int(getattr(settings, "BOT_WEBHOOK_ALERT_AUTO_DISABLED_24H", 1))
    )
    if auto_disabled_24h >= auto_disabled_threshold:
        alerts.append(
            {
                "code": "auto_disabled_bots",
                "severity": "critical",
                "message": "Bots auto-disabled due to webhook failures",
                "value": auto_disabled_24h,
                "threshold": auto_disabled_threshold,
            }
        )

    fails_1h_threshold = max(1, int(getattr(settings, "BOT_WEBHOOK_ALERT_FAILS_1H", 30)))
    if fails_1h >= fails_1h_threshold:
        alerts.append(
            {
                "code": "high_fail_volume",
                "severity": "warning",
                "message": "Webhook fail volume is high in last hour",
                "value": fails_1h,
                "threshold": fails_1h_threshold,
            }
        )

    fail_rate_threshold = max(
        1.0, float(getattr(settings, "BOT_WEBHOOK_ALERT_FAIL_RATE_PERCENT_1H", 20.0))
    )
    min_attempts = max(
        1, int(getattr(settings, "BOT_WEBHOOK_ALERT_MIN_ATTEMPTS_1H", 20))
    )
    if delivery_attempts_1h >= min_attempts and fail_rate_1h >= fail_rate_threshold:
        alerts.append(
            {
                "code": "high_fail_rate",
                "severity": "warning",
                "message": "Webhook fail-rate is high in last hour",
                "value": round(fail_rate_1h, 2),
                "threshold": fail_rate_threshold,
            }
        )

    dropped_total_threshold = max(
        1, int(getattr(settings, "BOT_WEBHOOK_ALERT_DROPPED_TOTAL", 10))
    )
    if dropped_total >= dropped_total_threshold:
        alerts.append(
            {
                "code": "dropped_deliveries",
                "severity": "warning",
                "message": "Dropped deliveries reached alert threshold",
                "value": dropped_total,
                "threshold": dropped_total_threshold,
            }
        )

    throttled_total_threshold = max(
        1, int(getattr(settings, "BOT_WEBHOOK_ALERT_THROTTLED_TOTAL", 50))
    )
    if throttled_total >= throttled_total_threshold:
        alerts.append(
            {
                "code": "throttled_deliveries",
                "severity": "warning",
                "message": "Per-bot webhook rate limit drops are high",
                "value": throttled_total,
                "threshold": throttled_total_threshold,
            }
        )

    alerts.sort(key=lambda item: 0 if item.get("severity") == "critical" else 1)
    return {
        "items": alerts,
        "snapshot": {
            "fails_1h": fails_1h,
            "ok_1h": ok_1h,
            "delivery_attempts_1h": delivery_attempts_1h,
            "fail_rate_percent_1h": round(fail_rate_1h, 2),
            "auto_disabled_24h": auto_disabled_24h,
            "dead_depth": dead_depth,
            "dropped_total": dropped_total,
            "throttled_total": throttled_total,
        },
    }


def _format_webhook_ops_lines(items: List[Dict[str, Any]]) -> List[str]:
    lines: List[str] = []
    for item in items:
        actor_name = (item.get("actor_name") or "").strip()
        actor_username = (item.get("actor_username") or "").strip()
        actor = " ".join(
            [
                actor_name,
                f"@{actor_username}" if actor_username else "",
            ]
        ).strip()
        lines.append(
            " | ".join(
                [
                    str(item.get("created_at") or "-"),
                    str(item.get("event_type") or "-"),
                    actor or "-",
                    json.dumps(item.get("metadata") or {}, ensure_ascii=False),
                ]
            )
        )
    return lines


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


def _log_webhook_system_action(
    db: Session,
    *,
    current_user: User,
    action: str,
    metadata: Optional[Dict[str, Any]] = None,
) -> None:
    AnalyticsService(db).log_event(
        event_type=action,
        entity_type="system",
        entity_id=0,
        user_id=current_user.id,
        author_id=current_user.id,
        metadata=metadata or {},
    )


def _clamp_limit(requested: int, *, max_allowed: int) -> int:
    safe_max = max(1, int(max_allowed))
    return max(1, min(int(requested), safe_max))


class ApproveRequest(BaseModel):
    comment: Optional[str] = None


class RejectRequest(BaseModel):
    reason: str  # spam | inappropriate | copyright | harassment | other
    comment: Optional[str] = None


class WarnUserRequest(BaseModel):
    message: Optional[str] = None


class BanUserRequest(BaseModel):
    reason: Optional[str] = None


class WebhookQueuePromoteRequest(BaseModel):
    limit: int = 500


class WebhookQueueClearRequest(BaseModel):
    include_delayed: bool = True


class WebhookDeadLetterActionRequest(BaseModel):
    limit: int = 100
    task_ids: Optional[List[str]] = None
    query: Optional[str] = None
    drop_reason: Optional[str] = None


class WebhookRecoveryPlaybookRequest(BaseModel):
    requeue_dead_limit: int = 300
    promote_delayed_limit: int = 500


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
    webhook_stats = webhook_queue_stats()
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
        "bot_webhook_queue": webhook_stats,
        "bot_webhook_alerts": _build_webhook_alerts(db, queue_stats=webhook_stats),
        "bot_webhook_recent_ops": _webhook_operations_page(db, limit=20)["items"],
    }


@router.post("/system/webhooks/promote-delayed")
async def promote_webhook_delayed(
    body: WebhookQueuePromoteRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    effective_limit = _clamp_limit(
        body.limit,
        max_allowed=getattr(settings, "BOT_WEBHOOK_OP_MAX_PROMOTE_LIMIT", 500),
    )
    moved = force_promote_delayed(limit=effective_limit)
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_queue_promote_delayed",
        metadata={
            "moved": moved,
            "limit_requested": body.limit,
            "limit_effective": effective_limit,
        },
    )
    db.commit()
    return {"moved": moved, "stats": webhook_queue_stats()}


@router.get("/system/webhooks/ops")
async def list_webhook_operations(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    query: Optional[str] = Query(default=None),
    event_type: Optional[str] = Query(default=None),
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    return _webhook_operations_page(
        db,
        limit=limit,
        offset=offset,
        query=query,
        event_type=event_type,
    )


@router.get("/system/webhooks/ops/export")
async def export_webhook_operations(
    limit: int = Query(default=500, ge=1, le=2000),
    query: Optional[str] = Query(default=None),
    event_type: Optional[str] = Query(default=None),
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    page = _webhook_operations_page(
        db,
        limit=limit,
        offset=0,
        query=query,
        event_type=event_type,
    )
    lines = _format_webhook_ops_lines(page["items"])
    return {
        "count": len(lines),
        "truncated": bool(page.get("has_more")),
        "content": "\n".join(lines),
    }


@router.get("/system/webhooks/ops/incident-report")
async def export_webhook_incident_report(
    limit: int = Query(default=200, ge=1, le=1000),
    query: Optional[str] = Query(default=None),
    event_type: Optional[str] = Query(default=None),
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    queue_stats = webhook_queue_stats()
    alerts = _build_webhook_alerts(db, queue_stats=queue_stats)
    page = _webhook_operations_page(
        db,
        limit=limit,
        offset=0,
        query=query,
        event_type=event_type,
    )
    ops_lines = _format_webhook_ops_lines(page["items"])
    header_lines = [
        f"generated_at={datetime.utcnow().isoformat()}Z",
        f"generated_by_user_id={current_user.id}",
        f"ops_count={len(ops_lines)}",
        f"ops_truncated={bool(page.get('has_more'))}",
        "",
        "[queue_stats]",
        json.dumps(queue_stats, ensure_ascii=False),
        "",
        "[alerts]",
        json.dumps(alerts, ensure_ascii=False),
        "",
        "[operations]",
    ]
    content = "\n".join(header_lines + ops_lines)
    return {
        "count": len(ops_lines),
        "truncated": bool(page.get("has_more")),
        "content": content,
    }


@router.post("/system/webhooks/clear")
async def clear_webhooks_queue(
    body: WebhookQueueClearRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    removed = clear_webhook_queue(include_delayed=body.include_delayed)
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_queue_clear",
        metadata={
            "queue_removed": int(removed.get("queue_removed") or 0),
            "delayed_removed": int(removed.get("delayed_removed") or 0),
            "include_delayed": body.include_delayed,
        },
    )
    db.commit()
    return {"removed": removed, "stats": webhook_queue_stats()}


@router.post("/system/webhooks/reset-metrics")
async def reset_webhooks_metrics(
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_metrics_reset",
    )
    db.commit()
    return {"stats": reset_webhook_metrics()}


@router.get("/system/webhooks/dead-letter")
async def get_webhooks_dead_letter(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    query: Optional[str] = Query(default=None),
    current_user: User = Depends(get_current_admin_required),
):
    page = webhook_dead_letter_page(limit=limit, offset=offset, query=query)
    return {
        "items": page["items"],
        "total": page["total"],
        "offset": page["offset"],
        "limit": page["limit"],
        "has_more": page["has_more"],
        "next_offset": page["next_offset"],
        "stats": webhook_queue_stats(),
    }


@router.post("/system/webhooks/dead-letter/requeue")
async def requeue_webhooks_dead_letter(
    body: WebhookDeadLetterActionRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    selected_count = len(body.task_ids or [])
    effective_limit = _clamp_limit(
        body.limit,
        max_allowed=getattr(settings, "BOT_WEBHOOK_OP_MAX_REQUEUE_LIMIT", 500),
    )
    moved = requeue_dead_letters(
        limit=effective_limit,
        task_ids=body.task_ids or None,
        query=body.query,
        drop_reason=body.drop_reason,
    )
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_dead_letter_requeue",
        metadata={
            "moved": moved,
            "limit_requested": body.limit,
            "limit_effective": effective_limit,
            "selected_task_ids": selected_count,
            "query": (body.query or "").strip() or None,
            "drop_reason": (body.drop_reason or "").strip() or None,
        },
    )
    db.commit()
    return {"moved": moved, "stats": webhook_queue_stats()}


@router.post("/system/webhooks/dead-letter/clear")
async def clear_webhooks_dead_letter(
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    removed = clear_dead_letters()
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_dead_letter_clear",
        metadata={"removed": removed},
    )
    db.commit()
    return {"removed": removed, "stats": webhook_queue_stats()}


@router.post("/system/webhooks/recovery-playbook")
async def run_webhooks_recovery_playbook(
    body: WebhookRecoveryPlaybookRequest,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    effective_requeue_limit = _clamp_limit(
        body.requeue_dead_limit,
        max_allowed=getattr(settings, "BOT_WEBHOOK_OP_MAX_RUNBOOK_REQUEUE_LIMIT", 500),
    )
    effective_promote_limit = _clamp_limit(
        body.promote_delayed_limit,
        max_allowed=getattr(settings, "BOT_WEBHOOK_OP_MAX_RUNBOOK_PROMOTE_LIMIT", 500),
    )
    requeued = requeue_dead_letters(limit=effective_requeue_limit)
    promoted = force_promote_delayed(limit=effective_promote_limit)
    stats = webhook_queue_stats()
    _log_webhook_system_action(
        db,
        current_user=current_user,
        action="bot_webhook_recovery_playbook_run",
        metadata={
            "requeued_dead_letters": requeued,
            "promoted_delayed": promoted,
            "requeue_dead_limit_requested": body.requeue_dead_limit,
            "requeue_dead_limit_effective": effective_requeue_limit,
            "promote_delayed_limit_requested": body.promote_delayed_limit,
            "promote_delayed_limit_effective": effective_promote_limit,
        },
    )
    db.commit()
    return {
        "status": "ok",
        "requeued_dead_letters": requeued,
        "promoted_delayed": promoted,
        "stats": stats,
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
