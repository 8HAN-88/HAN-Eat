"""Запись действий модераторов в audit log."""
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.models.moderation_audit_log import ModerationAuditLog


class ModerationAuditService:
    def __init__(self, db: Session):
        self.db = db

    def log(
        self,
        *,
        moderator_user_id: Optional[int],
        action: str,
        content_type: Optional[str] = None,
        content_id: Optional[int] = None,
        target_user_id: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.db.add(
            ModerationAuditLog(
                moderator_user_id=moderator_user_id,
                action=action,
                content_type=content_type,
                content_id=content_id,
                target_user_id=target_user_id,
                details=details or {},
            )
        )
