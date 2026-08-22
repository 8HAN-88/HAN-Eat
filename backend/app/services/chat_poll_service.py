"""Опросы в сообщениях чата."""
from __future__ import annotations

import copy
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.message_poll_vote import MessagePollVote


def _default_settings() -> Dict[str, Any]:
    return {
        "show_voter_names": True,
        "multiple_choice": False,
        "allow_add_options": False,
        "allow_change_vote": True,
        "random_order": False,
        "quiz_mode": False,
        "correct_option_indices": [],
        "time_limit_enabled": False,
        "duration_hours": 24,
        "hide_results_until_closed": False,
    }


def parse_closes_at(raw: Any) -> Optional[datetime]:
    if raw is None or raw == "":
        return None
    try:
        deadline = datetime.fromisoformat(str(raw))
    except Exception:
        return None
    if deadline.tzinfo is not None:
        deadline = deadline.astimezone(timezone.utc).replace(tzinfo=None)
    return deadline


def poll_deadline_passed(closes_at: Any) -> bool:
    deadline = parse_closes_at(closes_at)
    if deadline is None:
        return False
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return now >= deadline


def apply_poll_expiry_to_message(msg: Any) -> bool:
    """Persist is_closed when closes_at has passed. Returns True if content changed."""
    data = parse_poll_content(getattr(msg, "content", "") or "")
    if not data:
        return False
    poll = data["poll"]
    if poll.get("is_closed"):
        return False
    if not poll_deadline_passed(poll.get("closes_at")):
        return False
    poll["is_closed"] = True
    data["poll"] = poll
    msg.content = json.dumps(data, ensure_ascii=False)
    return True


def rebase_poll_closes_at(
    content: str, *, from_time: Optional[datetime] = None
) -> str:
    """Recompute closes_at from settings so scheduled polls start their timer at send."""
    data = parse_poll_content(content)
    if not data:
        return content
    poll = data["poll"]
    settings = poll.get("settings") or {}
    if not bool(settings.get("time_limit_enabled")):
        poll["closes_at"] = None
    else:
        hours = int(settings.get("duration_hours") or 24)
        base = from_time or datetime.now(timezone.utc).replace(tzinfo=None)
        if base.tzinfo is not None:
            base = base.astimezone(timezone.utc).replace(tzinfo=None)
        poll["closes_at"] = (base + timedelta(hours=hours)).isoformat()
    data["poll"] = poll
    return json.dumps(data, ensure_ascii=False)


def close_expired_polls(db: Session, limit: int = 40) -> List[Any]:
    """Best-effort sweep: close timed-out polls among recent poll messages."""
    from app.models.conversation import Message

    rows = (
        db.query(Message)
        .filter(Message.type == "poll", Message.deleted_at.is_(None))
        .order_by(Message.id.desc())
        .limit(max(limit * 5, 100))
        .all()
    )
    closed: List[Any] = []
    for msg in rows:
        if len(closed) >= limit:
            break
        if apply_poll_expiry_to_message(msg):
            closed.append(msg)
    if closed:
        db.flush()
    return closed


def poll_settings_need_premium(settings: Optional[Dict[str, Any]] = None) -> bool:
    merged = _default_settings()
    if settings:
        merged.update({k: v for k, v in settings.items() if k in merged})
    if not bool(merged.get("show_voter_names", True)):
        return True
    return any(
        bool(merged.get(key))
        for key in (
            "quiz_mode",
            "multiple_choice",
            "allow_add_options",
            "hide_results_until_closed",
            "time_limit_enabled",
            "random_order",
        )
    )


def build_poll_content(
    question: str,
    option_texts: List[str],
    description: str = "",
    settings: Optional[Dict[str, Any]] = None,
) -> str:
    q = (question or "").strip()
    desc = (description or "").strip()
    opts = [t.strip() for t in option_texts if t and t.strip()]
    if len(q) < 1:
        raise ValueError("poll_question_required")
    if len(opts) < 2:
        raise ValueError("poll_options_required")
    if len(opts) > 12:
        raise ValueError("poll_too_many_options")

    merged_settings = _default_settings()
    if settings:
        merged_settings.update({k: v for k, v in settings.items() if k in merged_settings})

    if bool(merged_settings.get("quiz_mode")):
        # Telegram quizzes are single-choice with one correct answer.
        merged_settings["multiple_choice"] = False
        merged_settings["allow_add_options"] = False
        merged_settings["allow_change_vote"] = False
        raw_correct = merged_settings.get("correct_option_indices") or []
        if not isinstance(raw_correct, list):
            raise ValueError("poll_quiz_correct_required")
        correct = []
        for item in raw_correct:
            try:
                idx = int(item)
            except (TypeError, ValueError):
                continue
            if 0 <= idx < len(opts) and idx not in correct:
                correct.append(idx)
        if not correct:
            raise ValueError("poll_quiz_correct_required")
        # Keep a single correct index for quiz mode.
        merged_settings["correct_option_indices"] = [correct[0]]

    closes_at = None
    if merged_settings.get("time_limit_enabled"):
        hours = int(merged_settings.get("duration_hours") or 24)
        closes_at = (
            datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=hours)
        ).isoformat()

    payload = {
        "poll": {
            "question": q,
            "description": desc,
            "options": [{"index": i, "text": text} for i, text in enumerate(opts)],
            "settings": merged_settings,
            "is_closed": False,
            "closes_at": closes_at,
        }
    }
    return json.dumps(payload, ensure_ascii=False)


def parse_poll_content(content: str) -> Optional[Dict[str, Any]]:
    if not content or not content.strip():
        return None
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    poll = data.get("poll")
    if not isinstance(poll, dict):
        return None
    return data


def _vote_counts(db: Session, message_ids: List[int]) -> Dict[int, Dict[int, int]]:
    if not message_ids:
        return {}
    rows = (
        db.query(
            MessagePollVote.message_id,
            MessagePollVote.option_index,
            func.count(MessagePollVote.id),
        )
        .filter(MessagePollVote.message_id.in_(message_ids))
        .group_by(MessagePollVote.message_id, MessagePollVote.option_index)
        .all()
    )
    out: Dict[int, Dict[int, int]] = {}
    for message_id, option_index, cnt in rows:
        out.setdefault(message_id, {})[option_index] = int(cnt)
    return out


def _user_votes(
    db: Session, message_ids: List[int], user_id: Optional[int]
) -> Dict[int, List[int]]:
    if not message_ids or user_id is None:
        return {}
    rows = (
        db.query(MessagePollVote.message_id, MessagePollVote.option_index)
        .filter(
            MessagePollVote.message_id.in_(message_ids),
            MessagePollVote.user_id == user_id,
        )
        .all()
    )
    out: Dict[int, List[int]] = {}
    for message_id, option_index in rows:
        out.setdefault(message_id, []).append(option_index)
    return out


def enrich_poll_content(
    db: Session,
    message_id: int,
    content: str,
    viewer_user_id: Optional[int],
    vote_counts: Optional[Dict[int, int]] = None,
    voted_indices: Optional[List[int]] = None,
) -> str:
    data = parse_poll_content(content)
    if not data:
        return content

    poll = data["poll"]
    stored_opts = poll.get("options")
    if not isinstance(stored_opts, list):
        return content

    if vote_counts is None:
        vote_counts = _vote_counts(db, [message_id]).get(message_id, {})
    if voted_indices is None and viewer_user_id is not None:
        voted_indices = _user_votes(db, [message_id], viewer_user_id).get(message_id, [])

    total = sum(vote_counts.values())
    options_out = []
    for raw in stored_opts:
        if not isinstance(raw, dict):
            continue
        idx = int(raw.get("index", 0))
        text = raw.get("text") or ""
        votes = vote_counts.get(idx, 0)
        pct = round((votes / total) * 100, 1) if total > 0 else 0.0
        options_out.append(
            {
                "index": idx,
                "text": text,
                "votes": votes,
                "percentage": pct,
            }
        )

    poll_out = copy.deepcopy(poll)
    poll_out["options"] = options_out
    poll_out["total_votes"] = total
    if voted_indices:
        poll_out["voted_option_indices"] = sorted(voted_indices)
        if len(voted_indices) == 1:
            poll_out["voted_option_index"] = voted_indices[0]
    data["poll"] = poll_out
    return json.dumps(data, ensure_ascii=False)


def enrich_messages_poll_batch(
    db: Session,
    messages: List[Any],
    viewer_user_id: Optional[int],
) -> Dict[int, str]:
    poll_ids = [m.id for m in messages if getattr(m, "type", None) == "poll"]
    if not poll_ids:
        return {}
    counts = _vote_counts(db, poll_ids)
    user_votes = _user_votes(db, poll_ids, viewer_user_id)
    out: Dict[int, str] = {}
    for m in messages:
        if m.id not in poll_ids:
            continue
        apply_poll_expiry_to_message(m)
        out[m.id] = enrich_poll_content(
            db,
            m.id,
            m.content,
            viewer_user_id,
            vote_counts=counts.get(m.id, {}),
            voted_indices=user_votes.get(m.id, []),
        )
    return out


def vote_on_message_poll(
    db: Session,
    message_id: int,
    user_id: int,
    option_index: int,
) -> str:
    from app.models.conversation import Message

    msg = db.query(Message).filter(Message.id == message_id).first()
    if not msg or msg.type != "poll":
        raise ValueError("not_poll_message")

    data = parse_poll_content(msg.content)
    if not data:
        raise ValueError("invalid_poll")

    poll = data["poll"]
    if apply_poll_expiry_to_message(msg):
        raise ValueError("poll_closed")
    # Re-parse after possible expiry persist.
    data = parse_poll_content(msg.content) or data
    poll = data["poll"]
    if poll.get("is_closed"):
        raise ValueError("poll_closed")

    stored_opts = poll.get("options") or []
    valid_indices = {
        int(o.get("index", i))
        for i, o in enumerate(stored_opts)
        if isinstance(o, dict)
    }
    if option_index not in valid_indices:
        raise ValueError("invalid_option")

    settings = poll.get("settings") or {}
    multiple = bool(settings.get("multiple_choice"))
    allow_change = bool(settings.get("allow_change_vote", True))

    existing = (
        db.query(MessagePollVote)
        .filter(
            MessagePollVote.message_id == message_id,
            MessagePollVote.user_id == user_id,
        )
        .all()
    )
    existing_indices = {v.option_index for v in existing}

    if option_index in existing_indices:
        if not allow_change:
            raise ValueError("vote_locked")
        for v in existing:
            if v.option_index == option_index:
                db.delete(v)
        db.flush()
    elif existing and not multiple:
        if not allow_change:
            raise ValueError("vote_locked")
        for v in existing:
            db.delete(v)
        db.flush()
        db.add(
            MessagePollVote(
                message_id=message_id,
                user_id=user_id,
                option_index=option_index,
            )
        )
    else:
        db.add(
            MessagePollVote(
                message_id=message_id,
                user_id=user_id,
                option_index=option_index,
            )
        )

    db.flush()
    return enrich_poll_content(db, message_id, msg.content, user_id)


def close_message_poll(
    db: Session,
    message_id: int,
    user_id: int,
) -> str:
    from app.models.conversation import Message

    msg = db.query(Message).filter(Message.id == message_id).first()
    if not msg or msg.type != "poll":
        raise ValueError("not_poll_message")

    if msg.sender_id != user_id:
        raise ValueError("forbidden")

    data = parse_poll_content(msg.content)
    if not data:
        raise ValueError("invalid_poll")

    poll = data["poll"]
    if poll.get("is_closed"):
        raise ValueError("poll_already_closed")

    poll["is_closed"] = True
    data["poll"] = poll
    msg.content = json.dumps(data, ensure_ascii=False)
    db.flush()
    return enrich_poll_content(db, message_id, msg.content, user_id)


def poll_preview_text(content: str) -> str:
    data = parse_poll_content(content)
    if not data:
        return "📊 Опрос"
    question = (data.get("poll") or {}).get("question") or ""
    q = question.strip()
    if q:
        from app.services.emoji_pack_service import preview_text_with_custom_emoji

        return f"📊 {preview_text_with_custom_emoji(q, limit=80)}"
    return "📊 Опрос"


def add_option_to_message_poll(
    db: Session,
    message_id: int,
    user_id: int,
    text: str,
) -> str:
    """Append a new option when allow_add_options is enabled."""
    from app.models.conversation import Message

    msg = db.query(Message).filter(Message.id == message_id).first()
    if not msg or msg.type != "poll":
        raise ValueError("not_poll_message")

    data = parse_poll_content(msg.content)
    if not data:
        raise ValueError("invalid_poll")

    poll = data["poll"]
    if apply_poll_expiry_to_message(msg):
        raise ValueError("poll_closed")
    data = parse_poll_content(msg.content) or data
    poll = data["poll"]
    if poll.get("is_closed"):
        raise ValueError("poll_closed")

    settings = poll.get("settings") or {}
    if not bool(settings.get("allow_add_options")):
        raise ValueError("add_options_disabled")

    cleaned = (text or "").strip()
    if len(cleaned) < 1:
        raise ValueError("empty_option")
    if len(cleaned) > 120:
        cleaned = cleaned[:120]
    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens(user_id, cleaned)

    raw_opts = poll.get("options") if isinstance(poll.get("options"), list) else []
    options: List[Dict[str, Any]] = []
    for raw in raw_opts:
        if not isinstance(raw, dict):
            continue
        idx = raw.get("index")
        if idx is None:
            continue
        opt_text = str(raw.get("text") or "").strip()
        if not opt_text:
            continue
        if opt_text.lower() == cleaned.lower():
            raise ValueError("duplicate_option")
        options.append({"index": int(idx), "text": opt_text})

    if len(options) >= 12:
        raise ValueError("poll_too_many_options")

    next_index = max((o["index"] for o in options), default=-1) + 1
    options.append({"index": next_index, "text": cleaned})
    poll["options"] = options
    poll.pop("total_votes", None)
    poll.pop("voted_option_indices", None)
    poll.pop("voted_option_index", None)
    data["poll"] = poll
    msg.content = json.dumps(data, ensure_ascii=False)
    db.flush()
    return enrich_poll_content(db, message_id, msg.content, user_id)


def list_message_poll_voters(
    db: Session,
    *,
    conversation_id: int,
    message_id: int,
    user_id: int,
) -> Dict[str, Any]:
    """Voters grouped by option (when show_voter_names is enabled)."""
    from app.models.conversation import ConversationMember, Message
    from app.models.user import User

    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
        .first()
    )
    if not member:
        raise ValueError("forbidden")

    msg = (
        db.query(Message)
        .filter(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
            Message.deleted_at.is_(None),
        )
        .first()
    )
    if not msg or msg.type != "poll":
        raise ValueError("not_poll_message")

    data = parse_poll_content(msg.content)
    if not data:
        raise ValueError("invalid_poll")
    poll = data.get("poll") or {}
    settings = poll.get("settings") or {}
    if not bool(settings.get("show_voter_names", True)):
        raise ValueError("voters_hidden")

    raw_options = poll.get("options") if isinstance(poll.get("options"), list) else []
    rows = (
        db.query(
            MessagePollVote.option_index,
            User.id,
            User.name,
            User.username,
            User.avatar_url,
        )
        .join(User, User.id == MessagePollVote.user_id)
        .filter(MessagePollVote.message_id == message_id)
        .order_by(MessagePollVote.created_at.desc())
        .all()
    )
    voters_by_option: Dict[int, List[Dict[str, Any]]] = {}
    for option_index, uid, name, username, avatar_url in rows:
        voters_by_option.setdefault(int(option_index), []).append(
            {
                "id": int(uid),
                "name": name,
                "username": username,
                "avatar_url": avatar_url,
            }
        )

    options_out: List[Dict[str, Any]] = []
    total = 0
    for item in raw_options:
        if not isinstance(item, dict):
            continue
        idx = item.get("index")
        if idx is None:
            continue
        index = int(idx)
        voters = voters_by_option.get(index, [])
        total += len(voters)
        options_out.append(
            {
                "index": index,
                "text": item.get("text") or "",
                "voters": voters,
            }
        )
    return {"options": options_out, "total": total}
