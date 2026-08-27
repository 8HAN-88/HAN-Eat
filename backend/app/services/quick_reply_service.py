"""Canned replies for the composer."""

from __future__ import annotations

from typing import List

from sqlalchemy.orm import Session

from app.models.quick_reply import QuickReply

MAX_QUICK_REPLIES = 20


class QuickReplyError(ValueError):
    pass


def list_replies(db: Session, user_id: int) -> List[QuickReply]:
    return (
        db.query(QuickReply)
        .filter(QuickReply.user_id == user_id)
        .order_by(QuickReply.sort_order.asc(), QuickReply.id.asc())
        .all()
    )


def create_reply(db: Session, user_id: int, title: str, text: str) -> QuickReply:
    from app.services.emoji_pack_service import (
        EmojiPackService,
        clip_preserving_custom_emoji,
        prepare_send_content,
    )

    emoji = EmojiPackService(db)
    emoji.require_send_tokens(user_id, title)
    # Composer may hold a share / private-reply / contact card. Gate the
    # user's own text; preview someone else's `[[e:id]]` so saving a
    # canned reply does not 403 without custom_emoji (69).
    text = prepare_send_content(emoji, user_id, "text", text)
    heading = (title or "").strip() or (text or "").strip()
    body = (text or "").strip()
    if not body:
        raise QuickReplyError("reply_text_required")
    count = db.query(QuickReply).filter(QuickReply.user_id == user_id).count()
    if count >= MAX_QUICK_REPLIES:
        raise QuickReplyError("quick_reply_limit")
    row = QuickReply(
        user_id=user_id,
        title=clip_preserving_custom_emoji(heading, 40),
        text=clip_preserving_custom_emoji(body, 400),
        sort_order=count,
    )
    db.add(row)
    db.flush()
    return row


def delete_reply(db: Session, user_id: int, reply_id: int) -> None:
    row = (
        db.query(QuickReply)
        .filter(QuickReply.id == reply_id, QuickReply.user_id == user_id)
        .first()
    )
    if not row:
        raise QuickReplyError("reply_not_found")
    db.delete(row)
    db.flush()
