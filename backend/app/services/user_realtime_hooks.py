"""SQLAlchemy hooks: публикуем realtime-события после commit новых уведомлений."""
from __future__ import annotations

from collections import defaultdict
from typing import DefaultDict, Dict, Optional

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.models.notification import Notification
from app.services.user_event_bus import publish_user_event

_pending: DefaultDict[int, Dict[int, Optional[str]]] = defaultdict(dict)


@event.listens_for(Session, "after_flush")
def _track_new_notifications(session: Session, flush_context) -> None:
    sid = id(session)
    for obj in session.new:
        if isinstance(obj, Notification):
            _pending[sid][obj.user_id] = obj.type


@event.listens_for(Session, "after_commit")
def _publish_after_commit(session: Session) -> None:
    sid = id(session)
    entries = _pending.pop(sid, {})
    for user_id, notification_type in entries.items():
        publish_user_event(
            user_id,
            {
                "event": "notification.new",
                "notification_type": notification_type,
            },
        )


@event.listens_for(Session, "after_rollback")
def _clear_pending(session: Session) -> None:
    _pending.pop(id(session), None)
