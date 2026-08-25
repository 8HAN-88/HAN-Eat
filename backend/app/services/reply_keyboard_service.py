"""Telegram-like ReplyKeyboard helpers (persistent above composer)."""
from __future__ import annotations

import json
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.models.conversation import ConversationMember
from app.models.user import User


def normalize_reply_keyboard(raw: Any) -> Optional[list[list[dict[str, str]]]]:
    """Normalize List[List[{text}]] — text-only buttons for MVP."""
    if raw is None:
        return None
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            return None
    if not isinstance(raw, list) or not raw:
        return None
    rows: list[list[dict[str, str]]] = []
    for row in raw:
        if not isinstance(row, list):
            continue
        out_row: list[dict[str, str]] = []
        for btn in row:
            if isinstance(btn, str):
                text = btn.strip()
            elif isinstance(btn, dict):
                text = str(btn.get("text") or "").strip()
            else:
                continue
            if not text:
                continue
            out_row.append({"text": text[:64]})
            if len(out_row) >= 12:
                break
        if out_row:
            rows.append(out_row)
        if len(rows) >= 8:
            break
    return rows or None


def member_reply_keyboard_labels(member: ConversationMember | None) -> set[str]:
    """Visible ReplyKeyboard button texts for this member."""
    keyboard = normalize_reply_keyboard(
        getattr(member, "reply_keyboard_json", None) if member else None
    )
    labels: set[str] = set()
    if not keyboard:
        return labels
    for row in keyboard:
        for btn in row:
            text = str(btn.get("text") or "").strip()
            if text:
                labels.add(text)
    return labels


def is_reply_keyboard_label(
    db: Session,
    conversation_id: int,
    user_id: int,
    text: Optional[str],
) -> bool:
    """True when `text` is a tap of the member's current ReplyKeyboard."""
    raw = (text or "").strip()
    if not raw or conversation_id <= 0 or user_id <= 0:
        return False
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
        .first()
    )
    return raw in member_reply_keyboard_labels(member)


def keyboard_payload_from_member(member: ConversationMember | None) -> dict[str, Any]:
    if member is None or not getattr(member, "reply_keyboard_json", None):
        return {
            "reply_keyboard": None,
            "reply_keyboard_one_time": False,
            "reply_keyboard_resize": True,
            "reply_keyboard_placeholder": None,
        }
    keyboard = normalize_reply_keyboard(member.reply_keyboard_json)
    return {
        "reply_keyboard": keyboard,
        "reply_keyboard_one_time": bool(
            getattr(member, "reply_keyboard_one_time", False)
        ),
        "reply_keyboard_resize": bool(
            getattr(member, "reply_keyboard_resize", True)
        ),
        "reply_keyboard_placeholder": getattr(
            member, "reply_keyboard_placeholder", None
        ),
    }


def set_member_reply_keyboard(
    db: Session,
    *,
    conversation_id: int,
    user_id: int,
    keyboard: Optional[list[list[dict[str, str]]]],
    one_time: bool = False,
    resize: bool = True,
    placeholder: Optional[str] = None,
    remove: bool = False,
) -> Optional[ConversationMember]:
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
        .first()
    )
    if member is None:
        return None
    user = db.query(User).filter(User.id == user_id).first()
    if user is not None and bool(getattr(user, "is_bot", False)):
        return member
    if remove or not keyboard:
        member.reply_keyboard_json = None
        member.reply_keyboard_one_time = False
        member.reply_keyboard_resize = True
        member.reply_keyboard_placeholder = None
    else:
        member.reply_keyboard_json = json.dumps(keyboard, ensure_ascii=False)
        member.reply_keyboard_one_time = bool(one_time)
        member.reply_keyboard_resize = bool(resize)
        ph = (placeholder or "").strip()[:64] or None
        member.reply_keyboard_placeholder = ph
    db.flush()
    return member


def clear_one_time_if_needed(
    db: Session,
    *,
    conversation_id: int,
    user_id: int,
) -> bool:
    """Clear reply keyboard after user replies when one_time is set."""
    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
        .first()
    )
    if member is None:
        return False
    if not getattr(member, "reply_keyboard_one_time", False):
        return False
    if not getattr(member, "reply_keyboard_json", None):
        return False
    member.reply_keyboard_json = None
    member.reply_keyboard_one_time = False
    member.reply_keyboard_resize = True
    member.reply_keyboard_placeholder = None
    db.flush()
    return True
