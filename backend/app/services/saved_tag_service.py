"""Saved Messages tags (Telegram Premium)."""

from __future__ import annotations

from typing import Dict, List, Optional

from sqlalchemy.orm import Session

from app.models.conversation import Conversation, ConversationMember, Message
from app.models.saved_tag import SavedMessageTag, SavedTag

MAX_TAGS_PER_USER = 100
MAX_TAGS_PER_MESSAGE = 10


class SavedTagError(ValueError):
    pass


def _saved_conversation_id(db: Session, user_id: int) -> Optional[int]:
    row = (
        db.query(Conversation.id)
        .join(
            ConversationMember,
            ConversationMember.conversation_id == Conversation.id,
        )
        .filter(
            Conversation.type == "saved",
            ConversationMember.user_id == user_id,
        )
        .first()
    )
    return int(row[0]) if row else None


def list_tags(db: Session, user_id: int) -> List[SavedTag]:
    return (
        db.query(SavedTag)
        .filter(SavedTag.user_id == user_id)
        .order_by(SavedTag.sort_order.asc(), SavedTag.id.asc())
        .all()
    )


def create_tag(db: Session, user_id: int, title: str, emoji: Optional[str] = None) -> SavedTag:
    heading = (title or "").strip()
    if not heading:
        raise SavedTagError("tag_title_required")
    count = db.query(SavedTag).filter(SavedTag.user_id == user_id).count()
    if count >= MAX_TAGS_PER_USER:
        raise SavedTagError("tag_limit")
    tag = SavedTag(
        user_id=user_id,
        title=heading[:40],
        emoji=(emoji or "").strip()[:8] or None,
        sort_order=count,
    )
    db.add(tag)
    db.flush()
    return tag


def delete_tag(db: Session, user_id: int, tag_id: int) -> None:
    tag = (
        db.query(SavedTag)
        .filter(SavedTag.id == tag_id, SavedTag.user_id == user_id)
        .first()
    )
    if not tag:
        raise SavedTagError("tag_not_found")
    db.delete(tag)
    db.flush()


def _assert_saved_message(db: Session, user_id: int, message_id: int) -> Message:
    saved_id = _saved_conversation_id(db, user_id)
    if not saved_id:
        raise SavedTagError("saved_not_found")
    msg = (
        db.query(Message)
        .filter(
            Message.id == message_id,
            Message.conversation_id == saved_id,
            Message.deleted_at.is_(None),
        )
        .first()
    )
    if not msg:
        raise SavedTagError("message_not_found")
    return msg


def set_message_tags(
    db: Session, user_id: int, message_id: int, tag_ids: List[int]
) -> List[int]:
    _assert_saved_message(db, user_id, message_id)
    wanted = []
    seen = set()
    for raw in tag_ids:
        tid = int(raw)
        if tid in seen:
            continue
        seen.add(tid)
        wanted.append(tid)
    if len(wanted) > MAX_TAGS_PER_MESSAGE:
        raise SavedTagError("too_many_tags")
    owned = {
        row.id
        for row in db.query(SavedTag)
        .filter(SavedTag.user_id == user_id, SavedTag.id.in_(wanted or [0]))
        .all()
    }
    if any(tid not in owned for tid in wanted):
        raise SavedTagError("tag_not_found")
    db.query(SavedMessageTag).filter(SavedMessageTag.message_id == message_id).delete(
        synchronize_session=False
    )
    for tid in wanted:
        db.add(SavedMessageTag(tag_id=tid, message_id=message_id))
    db.flush()
    return wanted


def tags_by_message_ids(db: Session, user_id: int, message_ids: List[int]) -> Dict[int, List[int]]:
    if not message_ids:
        return {}
    rows = (
        db.query(SavedMessageTag.message_id, SavedMessageTag.tag_id)
        .join(SavedTag, SavedTag.id == SavedMessageTag.tag_id)
        .filter(
            SavedTag.user_id == user_id,
            SavedMessageTag.message_id.in_(message_ids),
        )
        .all()
    )
    out: Dict[int, List[int]] = {mid: [] for mid in message_ids}
    for message_id, tag_id in rows:
        out.setdefault(int(message_id), []).append(int(tag_id))
    return out
