"""Жалобы пользователей и автоматическая эскалация в очередь."""
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.content_report import ContentReport
from app.models.moderation_queue import ModerationQueue
from app.models.post import Post
from app.models.comment import Comment
from app.models.user import User

# Порог: N жалоб за окно → скрыть из рекомендаций + очередь
REPORT_BURST_COUNT = 3
REPORT_BURST_HOURS = 24

VALID_REPORT_REASONS = frozenset(
    {
        "spam",
        "harassment",
        "nsfw",
        "violence",
        "misinformation",
        "scam",
        "inappropriate",
        "copyright",
        "other",
    }
)


class ContentReportService:
    def __init__(self, db: Session):
        self.db = db

    def create_report(
        self,
        *,
        content_type: str,
        content_id: int,
        reporter_user_id: int,
        reason: str,
        comment: Optional[str] = None,
    ) -> Tuple[ContentReport, bool]:
        """
        Создать жалобу. Возвращает (report, burst_triggered).
        """
        reason = reason if reason in VALID_REPORT_REASONS else "other"

        existing = (
            self.db.query(ContentReport)
            .filter(
                ContentReport.content_type == content_type,
                ContentReport.content_id == content_id,
                ContentReport.reporter_user_id == reporter_user_id,
                ContentReport.created_at
                >= datetime.utcnow() - timedelta(hours=REPORT_BURST_HOURS),
            )
            .first()
        )
        if existing:
            return existing, False

        report = ContentReport(
            content_type=content_type,
            content_id=content_id,
            reporter_user_id=reporter_user_id,
            reason=reason,
            comment=comment,
        )
        self.db.add(report)
        self.db.flush()

        burst = self._check_burst(content_type, content_id)
        if burst:
            self._escalate_to_queue(
                content_type=content_type,
                content_id=content_id,
                report_category=reason,
                flagged_by_user_id=reporter_user_id,
                comment=comment,
            )
        else:
            # Одна жалоба — тоже в очередь (как раньше), без скрытия ленты
            self._ensure_queue_item(
                content_type=content_type,
                content_id=content_id,
                report_category=reason,
                flagged_by_user_id=reporter_user_id,
                comment=comment,
                hide_from_feed=False,
            )

        return report, burst

    def _check_burst(self, content_type: str, content_id: int) -> bool:
        since = datetime.utcnow() - timedelta(hours=REPORT_BURST_HOURS)
        count = (
            self.db.query(func.count(ContentReport.id))
            .filter(
                ContentReport.content_type == content_type,
                ContentReport.content_id == content_id,
                ContentReport.created_at >= since,
            )
            .scalar()
            or 0
        )
        return count >= REPORT_BURST_COUNT

    def _escalate_to_queue(
        self,
        *,
        content_type: str,
        content_id: int,
        report_category: str,
        flagged_by_user_id: int,
        comment: Optional[str],
    ) -> None:
        author_id = self._author_id(content_type, content_id)
        self._ensure_queue_item(
            content_type=content_type,
            content_id=content_id,
            report_category=report_category,
            flagged_by_user_id=flagged_by_user_id,
            comment=comment,
            hide_from_feed=True,
            author_id=author_id,
        )

    def _ensure_queue_item(
        self,
        *,
        content_type: str,
        content_id: int,
        report_category: str,
        flagged_by_user_id: int,
        comment: Optional[str],
        hide_from_feed: bool,
        author_id: Optional[int] = None,
    ) -> None:
        author_id = author_id or self._author_id(content_type, content_id)

        pending = (
            self.db.query(ModerationQueue)
            .filter(
                ModerationQueue.content_type == content_type,
                ModerationQueue.content_id == content_id,
                ModerationQueue.status == "pending",
            )
            .first()
        )
        if not pending:
            self.db.add(
                ModerationQueue(
                    content_type=content_type,
                    content_id=content_id,
                    user_id=author_id,
                    status="pending",
                    reason="reported",
                    flagged_by_user_id=flagged_by_user_id,
                    moderation_comment=comment,
                    report_category=report_category,
                    ai_decision="warning",
                )
            )
        else:
            if not pending.flagged_by_user_id:
                pending.flagged_by_user_id = flagged_by_user_id
            if report_category:
                pending.report_category = report_category
            if comment and comment.strip():
                pending.moderation_comment = comment.strip()
            if pending.reason != "reported":
                pending.reason = "reported"

        if hide_from_feed and content_type == "post":
            post = self.db.query(Post).filter(Post.id == content_id).first()
            if post:
                post.hidden_from_recommendations = True
                if post.status == "published":
                    post.status = "pending"

    def _author_id(self, content_type: str, content_id: int) -> Optional[int]:
        if content_type == "post":
            p = self.db.query(Post).filter(Post.id == content_id).first()
            return p.user_id if p else None
        if content_type == "comment":
            c = self.db.query(Comment).filter(Comment.id == content_id).first()
            return c.user_id if c else None
        if content_type == "channel":
            from app.models.community import Channel

            ch = self.db.query(Channel).filter(Channel.id == content_id).first()
            return ch.admin_user_id if ch else None
        return None

    def list_recent_reports(
        self,
        content_type: str,
        content_id: int,
        *,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """Последние жалобы на контент (для модерации)."""
        reports = (
            self.db.query(ContentReport)
            .filter(
                ContentReport.content_type == content_type,
                ContentReport.content_id == content_id,
            )
            .order_by(ContentReport.created_at.desc())
            .limit(limit)
            .all()
        )
        if not reports:
            return []

        reporter_ids = {r.reporter_user_id for r in reports if r.reporter_user_id}
        users_by_id: Dict[int, User] = {}
        if reporter_ids:
            users = self.db.query(User).filter(User.id.in_(reporter_ids)).all()
            users_by_id = {u.id: u for u in users}

        reason_labels = {
            "spam": "Спам",
            "harassment": "Оскорбления",
            "nsfw": "NSFW",
            "violence": "Насилие",
            "misinformation": "Ложная информация",
            "scam": "Мошенничество",
            "inappropriate": "Неподходящий контент",
            "copyright": "Авторские права",
            "other": "Другое",
        }

        out: List[Dict[str, Any]] = []
        for r in reports:
            reporter = users_by_id.get(r.reporter_user_id) if r.reporter_user_id else None
            if reporter:
                reporter_payload = {
                    "id": reporter.id,
                    "name": reporter.name,
                    "username": reporter.username,
                }
                reporter_display = (
                    f"{reporter.name} (@{reporter.username})"
                    if reporter.username
                    else reporter.name
                )
            elif r.reporter_user_id:
                reporter_payload = {
                    "id": r.reporter_user_id,
                    "name": f"Пользователь #{r.reporter_user_id}",
                    "username": None,
                }
                reporter_display = reporter_payload["name"]
            else:
                reporter_payload = None
                reporter_display = "Неизвестный пользователь"

            comment = (r.comment or "").strip() or None
            out.append(
                {
                    "id": r.id,
                    "reason": r.reason,
                    "reason_label": reason_labels.get(r.reason, r.reason),
                    "comment": comment,
                    "reporter_user_id": r.reporter_user_id,
                    "reporter": reporter_payload,
                    "reporter_display_name": reporter_display,
                    "created_at": r.created_at.isoformat() if r.created_at else None,
                }
            )
        return out

    def report_count(self, content_type: str, content_id: int, hours: int = 24) -> int:
        since = datetime.utcnow() - timedelta(hours=hours)
        return (
            self.db.query(func.count(ContentReport.id))
            .filter(
                ContentReport.content_type == content_type,
                ContentReport.content_id == content_id,
                ContentReport.created_at >= since,
            )
            .scalar()
            or 0
        )
