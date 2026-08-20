"""Colored chat tags for the inbox (Telegram Premium)."""

from __future__ import annotations

from typing import Dict, List

from sqlalchemy.orm import Session

from app.models.chat_tag import ChatTag, ConversationChatTag

MAX_TAGS_PER_USER = 20
MAX_TAGS_PER_CHAT = 3
ALLOWED_COLORS = frozenset(
    {"red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"}
)


class ChatTagError(ValueError):
    pass


def _normalize_color(value: str | None) -> str:
    key = (value or "blue").strip().lower()
    if key not in ALLOWED_COLORS:
        raise ChatTagError("bad_tag_color")
    return key


def list_tags(db: Session, user_id: int) -> List[ChatTag]:
    return (
        db.query(ChatTag)
        .filter(ChatTag.user_id == user_id)
        .order_by(ChatTag.sort_order.asc(), ChatTag.id.asc())
        .all()
    )


def create_tag(db: Session, user_id: int, title: str, color: str | None = None) -> ChatTag:
    heading = (title or "").strip()
    if not heading:
        raise ChatTagError("tag_title_required")
    count = db.query(ChatTag).filter(ChatTag.user_id == user_id).count()
    if count >= MAX_TAGS_PER_USER:
        raise ChatTagError("tag_limit")
    tag = ChatTag(
        user_id=user_id,
        title=heading[:40],
        color=_normalize_color(color),
        sort_order=count,
    )
    db.add(tag)
    db.flush()
    return tag


def delete_tag(db: Session, user_id: int, tag_id: int) -> None:
    tag = (
        db.query(ChatTag)
        .filter(ChatTag.id == tag_id, ChatTag.user_id == user_id)
        .first()
    )
    if not tag:
        raise ChatTagError("tag_not_found")
    db.delete(tag)
    db.flush()


def tag_ids_for_conversation(db: Session, user_id: int, conversation_id: int) -> List[int]:
    rows = (
        db.query(ConversationChatTag.tag_id)
        .filter(
            ConversationChatTag.user_id == user_id,
            ConversationChatTag.conversation_id == conversation_id,
        )
        .all()
    )
    return [int(row[0]) for row in rows]


def tag_ids_by_conversation(
    db: Session, user_id: int, conversation_ids: List[int]
) -> Dict[int, List[int]]:
    if not conversation_ids:
        return {}
    rows = (
        db.query(ConversationChatTag.conversation_id, ConversationChatTag.tag_id)
        .filter(
            ConversationChatTag.user_id == user_id,
            ConversationChatTag.conversation_id.in_(conversation_ids),
        )
        .all()
    )
    mapped: Dict[int, List[int]] = {int(cid): [] for cid in conversation_ids}
    for conversation_id, tag_id in rows:
        mapped.setdefault(int(conversation_id), []).append(int(tag_id))
    return mapped


def set_conversation_tags(
    db: Session,
    user_id: int,
    conversation_id: int,
    tag_ids: List[int],
) -> List[int]:
    unique: List[int] = []
    seen = set()
    for raw in tag_ids:
        tid = int(raw)
        if tid in seen:
            continue
        seen.add(tid)
        unique.append(tid)
    if len(unique) > MAX_TAGS_PER_CHAT:
        raise ChatTagError("chat_tag_limit")
    owned = {
        int(row.id)
        for row in db.query(ChatTag)
        .filter(ChatTag.user_id == user_id, ChatTag.id.in_(unique or [0]))
        .all()
    }
    if unique and owned != set(unique):
        raise ChatTagError("tag_not_found")
    (
        db.query(ConversationChatTag)
        .filter(
            ConversationChatTag.user_id == user_id,
            ConversationChatTag.conversation_id == conversation_id,
        )
        .delete(synchronize_session=False)
    )
    for tid in unique:
        db.add(
            ConversationChatTag(
                user_id=user_id,
                conversation_id=conversation_id,
                tag_id=tid,
            )
        )
    db.flush()
    return unique
