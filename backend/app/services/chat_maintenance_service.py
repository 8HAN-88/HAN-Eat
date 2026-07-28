"""Background chat maintenance: due scheduled messages + TTL auto-delete fanout."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.models.conversation import ConversationMember
from app.services.chat_event_bus import publish as publish_chat_event
from app.services.chat_service import ChatService
from app.services.user_event_bus import publish_user_event

logger = logging.getLogger(__name__)


def _message_payload(msg) -> Dict[str, Any]:
    inline_keyboard = None
    raw_keyboard = getattr(msg, "inline_keyboard_json", None)
    if raw_keyboard:
        try:
            parsed = json.loads(raw_keyboard)
            if isinstance(parsed, list):
                inline_keyboard = parsed
        except Exception:
            inline_keyboard = None
    return {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_id": msg.sender_id,
        "type": msg.type,
        "content": msg.content,
        "media_url": msg.media_url,
        "reply_to_message_id": msg.reply_to_message_id,
        "forward_from_user_id": getattr(msg, "forward_from_user_id", None),
        "forward_from_name": getattr(msg, "forward_from_name", None),
        "forwarded_from_message_id": getattr(msg, "forwarded_from_message_id", None),
        "forwarded_from_conversation_id": None,
        "inline_keyboard": inline_keyboard,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "edited_at": msg.edited_at.isoformat()
        if getattr(msg, "edited_at", None)
        else None,
        "disable_webpage_preview": bool(
            getattr(msg, "disable_webpage_preview", False)
        ),
        "reactions": [],
    }


def _notify_chat_inbox(
    db: Session, conversation_id: int, sender_id: Optional[int] = None
) -> None:
    member_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == conversation_id)
        .all()
    )
    for (user_id,) in member_ids:
        if sender_id is not None and user_id == sender_id:
            continue
        publish_user_event(
            user_id,
            {
                "event": "chat.inbox",
                "conversation_id": conversation_id,
            },
        )


def run_chat_maintenance(db: Session) -> Dict[str, int]:
    """Dispatch due scheduled messages and purge TTL-expired ones with SSE fanout."""
    from app.services.chat_poll_service import close_expired_polls, enrich_poll_content

    svc = ChatService(db)
    dispatched = svc.dispatch_due_scheduled_messages(limit=40)
    purged = svc.purge_due_auto_deleted_messages(limit_conversations=80)
    closed_polls = close_expired_polls(db, limit=40)

    for msg in dispatched:
        publish_chat_event(
            msg.conversation_id,
            {"type": "message.new", "message": _message_payload(msg)},
        )
        _notify_chat_inbox(db, msg.conversation_id, sender_id=msg.sender_id)

    for conversation_id, message_ids in purged.items():
        for message_id in message_ids:
            publish_chat_event(
                conversation_id,
                {"type": "message.deleted", "message_id": message_id},
            )
        _notify_chat_inbox(db, conversation_id, sender_id=None)

    for msg in closed_polls:
        payload = _message_payload(msg)
        try:
            payload["content"] = enrich_poll_content(
                db, msg.id, msg.content, None
            )
        except Exception:
            pass
        publish_chat_event(
            msg.conversation_id,
            {"type": "message.edited", "message": payload},
        )

    stats = {
        "scheduled_sent": len(dispatched),
        "ttl_purged": sum(len(ids) for ids in purged.values()),
        "ttl_conversations": len(purged),
        "polls_closed": len(closed_polls),
    }
    if (
        stats["scheduled_sent"]
        or stats["ttl_purged"]
        or stats["polls_closed"]
    ):
        logger.info(
            "Chat maintenance: scheduled_sent=%s ttl_purged=%s polls_closed=%s",
            stats["scheduled_sent"],
            stats["ttl_purged"],
            stats["polls_closed"],
        )
    return stats
