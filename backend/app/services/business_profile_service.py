"""Telegram Business profile + inbound auto-replies."""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Optional
from urllib.parse import urlparse
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.orm import Session

from app.models.conversation import Conversation, Message
from app.models.user import User
from app.models.user_business import BusinessAutoReply, UserBusinessSettings
from app.services.last_seen_privacy import is_owner_contact
from app.services.subscription_service import SubscriptionService

GREETING_DAYS = (7, 14, 21, 28)
AWAY_MODES = ("manual", "outside_hours")
AWAY_COOLDOWN = timedelta(hours=12)
DM_EVERYBODY = "everybody"
DM_CONTACTS = "contacts"
DM_NOBODY = "nobody"
ALLOWED_DM_PRIVACY = frozenset({DM_EVERYBODY, DM_CONTACTS, DM_NOBODY})
_TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


class BusinessError(ValueError):
    pass


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def normalize_dm_privacy(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    key = str(value).strip().lower()
    if key not in ALLOWED_DM_PRIVACY:
        raise ValueError("invalid_dm_privacy")
    return key


def resolve_dm_privacy(user) -> str:
    raw = getattr(user, "dm_privacy", None)
    if isinstance(raw, str):
        key = raw.strip().lower()
        if key in ALLOWED_DM_PRIVACY:
            return key
    return DM_EVERYBODY


def can_start_dm(db: Session, actor_id: int, target) -> bool:
    if int(actor_id) == int(getattr(target, "id", 0) or 0):
        return True
    privacy = resolve_dm_privacy(target)
    if privacy == DM_EVERYBODY:
        return True
    if privacy == DM_NOBODY:
        return False
    return is_owner_contact(db, int(target.id), int(actor_id))


def get_or_create_settings(db: Session, user_id: int) -> UserBusinessSettings:
    row = (
        db.query(UserBusinessSettings)
        .filter(UserBusinessSettings.user_id == user_id)
        .first()
    )
    if row is None:
        row = UserBusinessSettings(user_id=user_id)
        db.add(row)
        db.flush()
    return row


def _parse_hhmm(value: str) -> Optional[tuple[int, int]]:
    match = _TIME_RE.match((value or "").strip())
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def normalize_hours(raw) -> dict[str, Any]:
    data = raw
    if isinstance(raw, str):
        raw = raw.strip()
        if not raw:
            return {"timezone": "UTC", "intervals": []}
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise BusinessError("invalid_hours") from exc
    if data is None:
        return {"timezone": "UTC", "intervals": []}
    if not isinstance(data, dict):
        raise BusinessError("invalid_hours")
    tz_name = str(data.get("timezone") or "UTC").strip() or "UTC"
    try:
        ZoneInfo(tz_name)
    except ZoneInfoNotFoundError as exc:
        raise BusinessError("invalid_timezone") from exc
    intervals = []
    for item in data.get("intervals") or []:
        if not isinstance(item, dict):
            continue
        try:
            dow = int(item.get("dow"))
        except (TypeError, ValueError):
            continue
        if dow < 0 or dow > 6:
            continue
        start = _parse_hhmm(str(item.get("start") or ""))
        end = _parse_hhmm(str(item.get("end") or ""))
        if not start or not end:
            continue
        start_m = start[0] * 60 + start[1]
        end_m = end[0] * 60 + end[1]
        if end_m <= start_m:
            continue
        intervals.append(
            {
                "dow": dow,
                "start": f"{start[0]:02d}:{start[1]:02d}",
                "end": f"{end[0]:02d}:{end[1]:02d}",
            }
        )
    intervals.sort(key=lambda i: (i["dow"], i["start"]))
    return {"timezone": tz_name, "intervals": intervals[:21]}


def hours_from_row(row: UserBusinessSettings) -> dict[str, Any]:
    return normalize_hours(row.hours_json)


def is_open_now(hours: dict[str, Any], now: Optional[datetime] = None) -> bool:
    intervals = hours.get("intervals") or []
    if not intervals:
        return True
    try:
        tz = ZoneInfo(str(hours.get("timezone") or "UTC"))
    except ZoneInfoNotFoundError:
        tz = timezone.utc
    stamp = now or datetime.now(timezone.utc)
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    local = stamp.astimezone(tz)
    minutes = local.hour * 60 + local.minute
    dow = local.weekday()
    for item in intervals:
        if int(item["dow"]) != dow:
            continue
        start = _parse_hhmm(item["start"])
        end = _parse_hhmm(item["end"])
        if not start or not end:
            continue
        start_m = start[0] * 60 + start[1]
        end_m = end[0] * 60 + end[1]
        if start_m <= minutes < end_m:
            return True
    return False


def normalize_website(value: Optional[str]) -> Optional[str]:
    raw = (value or "").strip()
    if not raw:
        return None
    if "://" not in raw:
        raw = f"https://{raw}"
    parsed = urlparse(raw)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise BusinessError("invalid_website")
    return raw[:200]


def _bool(value) -> bool:
    return bool(value)


def owner_settings_payload(db: Session, user: User) -> dict[str, Any]:
    billing = SubscriptionService(db)
    row = get_or_create_settings(db, user.id)
    hours = hours_from_row(row)
    slugs = (
        "business_greeting",
        "business_away",
        "business_hours",
        "business_location",
        "business_intro",
        "business_bot",
        "dm_privacy",
        "profile_website",
    )
    return {
        "greeting_enabled": _bool(row.greeting_enabled),
        "greeting_text": row.greeting_text or "",
        "greeting_inactivity_days": int(row.greeting_inactivity_days or 7),
        "away_enabled": _bool(row.away_enabled),
        "away_text": row.away_text or "",
        "away_mode": row.away_mode if row.away_mode in AWAY_MODES else "manual",
        "hours": hours,
        "is_open": is_open_now(hours),
        "location_lat": row.location_lat,
        "location_lng": row.location_lng,
        "location_address": row.location_address or "",
        "intro_title": row.intro_title or "",
        "intro_text": row.intro_text or "",
        "intro_sticker_url": row.intro_sticker_url or "",
        "support_bot": _bot_brief(db, row.support_bot_id),
        "website_url": row.website_url or "",
        "dm_privacy": resolve_dm_privacy(user),
        "unlocked": {slug: billing.has_feature(user.id, slug) for slug in slugs},
    }


def public_payload(db: Session, user: User) -> dict[str, Any]:
    billing = SubscriptionService(db)
    row = (
        db.query(UserBusinessSettings)
        .filter(UserBusinessSettings.user_id == user.id)
        .first()
    )
    out: dict[str, Any] = {}
    if billing.has_feature(user.id, "business_hours"):
        hours = hours_from_row(row) if row else {"timezone": "UTC", "intervals": []}
        if hours.get("intervals"):
            out["hours"] = hours
            out["is_open"] = is_open_now(hours)
    if billing.has_feature(user.id, "business_location") and row:
        if row.location_lat is not None and row.location_lng is not None:
            out["location"] = {
                "lat": float(row.location_lat),
                "lng": float(row.location_lng),
                "address": row.location_address or "",
            }
    if billing.has_feature(user.id, "business_intro") and row:
        title = (row.intro_title or "").strip()
        text = (row.intro_text or "").strip()
        sticker = (row.intro_sticker_url or "").strip()
        if title or text or sticker:
            out["intro"] = {
                "title": title,
                "text": text,
                "sticker_url": sticker,
            }
    if billing.has_feature(user.id, "business_bot") and row:
        bot = _bot_brief(db, row.support_bot_id)
        if bot is not None:
            out["support_bot"] = bot
    if billing.has_feature(user.id, "profile_website") and row:
        if row.website_url:
            out["website_url"] = row.website_url
    return out


def _bot_brief(db: Session, bot_id: Optional[int]) -> Optional[dict[str, Any]]:
    if not bot_id:
        return None
    bot = (
        db.query(User)
        .filter(User.id == int(bot_id), User.is_bot == True)  # noqa: E712
        .first()
    )
    if not bot:
        return None
    return {
        "id": bot.id,
        "name": bot.name,
        "username": bot.bot_username or bot.username,
        "avatar_url": bot.bot_avatar_url or bot.avatar_url,
    }


def _own_bot(db: Session, owner_id: int, bot_id: int) -> User:
    bot = (
        db.query(User)
        .filter(
            User.id == bot_id,
            User.is_bot == True,  # noqa: E712
            User.created_by_user_id == owner_id,
        )
        .first()
    )
    if not bot:
        raise BusinessError("bot_not_found")
    return bot


def update_settings(db: Session, user: User, body: dict[str, Any]) -> dict[str, Any]:
    from app.services.emoji_pack_service import EmojiPackService

    billing = SubscriptionService(db)
    row = get_or_create_settings(db, user.id)

    if "greeting_enabled" in body or "greeting_text" in body or "greeting_inactivity_days" in body:
        enabled = _bool(body["greeting_enabled"]) if "greeting_enabled" in body else _bool(row.greeting_enabled)
        text = (
            str(body.get("greeting_text") or "").strip()[:400]
            if "greeting_text" in body
            else (row.greeting_text or "")
        )
        days = int(row.greeting_inactivity_days or 7)
        if "greeting_inactivity_days" in body:
            try:
                days = int(body.get("greeting_inactivity_days") or 7)
            except (TypeError, ValueError) as exc:
                raise BusinessError("invalid_greeting_days") from exc
            if days not in GREETING_DAYS:
                raise BusinessError("invalid_greeting_days")
        EmojiPackService(db).require_send_tokens_http(user.id, text)
        if (enabled or text) and not billing.has_feature(user.id, "business_greeting"):
            billing.require_feature(
                user.id,
                "business_greeting",
                "Приветствие доступно с уровня 61",
            )
        row.greeting_enabled = bool(enabled and text)
        row.greeting_text = text or None
        row.greeting_inactivity_days = days

    if "away_enabled" in body or "away_text" in body or "away_mode" in body:
        enabled = _bool(body["away_enabled"]) if "away_enabled" in body else _bool(row.away_enabled)
        text = (
            str(body.get("away_text") or "").strip()[:400]
            if "away_text" in body
            else (row.away_text or "")
        )
        mode = str(body.get("away_mode") or row.away_mode or "manual").strip()
        if mode not in AWAY_MODES:
            raise BusinessError("invalid_away_mode")
        EmojiPackService(db).require_send_tokens_http(user.id, text)
        if (enabled or text or mode != "manual") and not billing.has_feature(
            user.id, "business_away"
        ):
            billing.require_feature(
                user.id,
                "business_away",
                "Автоответ «меня нет» доступен с уровня 62",
            )
        row.away_enabled = bool(enabled and text)
        row.away_text = text or None
        row.away_mode = mode

    if "hours" in body:
        hours = normalize_hours(body.get("hours"))
        if hours["intervals"] and not billing.has_feature(user.id, "business_hours"):
            billing.require_feature(
                user.id,
                "business_hours",
                "Часы работы доступны с уровня 63",
            )
        row.hours_json = json.dumps(hours, ensure_ascii=False)

    if any(k in body for k in ("location_lat", "location_lng", "location_address")):
        lat = body.get("location_lat", row.location_lat)
        lng = body.get("location_lng", row.location_lng)
        address = (
            str(body.get("location_address") or "").strip()[:120]
            if "location_address" in body
            else (row.location_address or "")
        )
        EmojiPackService(db).require_send_tokens_http(user.id, address)
        if lat is None or lng is None or lat == "" or lng == "":
            row.location_lat = None
            row.location_lng = None
            row.location_address = address or None
        else:
            try:
                lat_f = float(lat)
                lng_f = float(lng)
            except (TypeError, ValueError) as exc:
                raise BusinessError("invalid_location") from exc
            if lat_f < -90 or lat_f > 90 or lng_f < -180 or lng_f > 180:
                raise BusinessError("invalid_location")
            if not billing.has_feature(user.id, "business_location"):
                billing.require_feature(
                    user.id,
                    "business_location",
                    "Адрес на карте доступен с уровня 64",
                )
            row.location_lat = lat_f
            row.location_lng = lng_f
            row.location_address = address or None

    if any(k in body for k in ("intro_title", "intro_text", "intro_sticker_url")):
        title = (
            str(body.get("intro_title") or "").strip()[:40]
            if "intro_title" in body
            else (row.intro_title or "")
        )
        text = (
            str(body.get("intro_text") or "").strip()[:200]
            if "intro_text" in body
            else (row.intro_text or "")
        )
        sticker = (
            str(body.get("intro_sticker_url") or "").strip()[:1024]
            if "intro_sticker_url" in body
            else (row.intro_sticker_url or "")
        )
        EmojiPackService(db).require_send_tokens_http(user.id, title, text)
        if (title or text or sticker) and not billing.has_feature(user.id, "business_intro"):
            billing.require_feature(
                user.id,
                "business_intro",
                "Стартовая страница доступна с уровня 65",
            )
        row.intro_title = title or None
        row.intro_text = text or None
        row.intro_sticker_url = sticker or None

    if "support_bot_id" in body:
        raw = body.get("support_bot_id")
        if raw in (None, "", 0, "0"):
            row.support_bot_id = None
        else:
            if not billing.has_feature(user.id, "business_bot"):
                billing.require_feature(
                    user.id,
                    "business_bot",
                    "Бот поддержки доступен с уровня 66",
                )
            bot = _own_bot(db, user.id, int(raw))
            row.support_bot_id = bot.id

    if "website_url" in body:
        url = normalize_website(body.get("website_url"))
        if url and not billing.has_feature(user.id, "profile_website"):
            billing.require_feature(
                user.id,
                "profile_website",
                "Сайт в профиле доступен с уровня 68",
            )
        row.website_url = url

    db.flush()
    return owner_settings_payload(db, user)


def _last_auto(db: Session, owner_id: int, peer_id: int, kind: str) -> Optional[BusinessAutoReply]:
    return (
        db.query(BusinessAutoReply)
        .filter(
            BusinessAutoReply.owner_user_id == owner_id,
            BusinessAutoReply.peer_user_id == peer_id,
            BusinessAutoReply.kind == kind,
        )
        .first()
    )


def _mark_auto(db: Session, owner_id: int, peer_id: int, kind: str) -> None:
    row = _last_auto(db, owner_id, peer_id, kind)
    if row is None:
        row = BusinessAutoReply(
            owner_user_id=owner_id,
            peer_user_id=peer_id,
            kind=kind,
            sent_at=_now(),
        )
        db.add(row)
    else:
        row.sent_at = _now()
    db.flush()


def _auto_text_for_sender(db: Session, sender_id: int, text: str) -> str:
    raw = (text or "").strip()
    if not raw:
        return raw
    from app.services.emoji_pack_service import (
        EmojiPackService,
        preview_text_with_custom_emoji,
    )

    try:
        EmojiPackService(db).require_send_tokens(sender_id, raw)
        return raw
    except ValueError:
        return preview_text_with_custom_emoji(raw)


def _insert_auto_text(db: Session, conversation_id: int, sender_id: int, text: str) -> Message:
    clean = _auto_text_for_sender(db, sender_id, text)
    msg = Message(
        conversation_id=conversation_id,
        sender_id=sender_id,
        type="text",
        content=clean[:4000],
        created_at=_now(),
    )
    db.add(msg)
    db.flush()
    return msg


def maybe_auto_reply(
    db: Session,
    conv: Conversation,
    sender_id: int,
) -> list[Message]:
    if conv is None or conv.type != "direct":
        return []
    owner_id = (
        conv.direct_user_high_id
        if conv.direct_user_low_id == sender_id
        else conv.direct_user_low_id
    )
    if not owner_id or int(owner_id) == int(sender_id):
        return []
    sender = db.query(User).filter(User.id == sender_id).first()
    if sender is None or bool(getattr(sender, "is_bot", False)):
        return []
    owner = db.query(User).filter(User.id == owner_id).first()
    if owner is None:
        return []
    billing = SubscriptionService(db)
    row = (
        db.query(UserBusinessSettings)
        .filter(UserBusinessSettings.user_id == owner.id)
        .first()
    )
    if row is None:
        return []
    sent: list[Message] = []
    now = _now()

    owner_last = (
        db.query(Message.created_at)
        .filter(
            Message.conversation_id == conv.id,
            Message.sender_id == owner.id,
            Message.deleted_at.is_(None),
        )
        .order_by(Message.created_at.desc(), Message.id.desc())
        .first()
    )
    first_contact = owner_last is None or owner_last[0] is None
    days = int(row.greeting_inactivity_days or 7)
    if days not in GREETING_DAYS:
        days = 7
    inactive = False
    if owner_last and owner_last[0] is not None:
        inactive = owner_last[0] <= now - timedelta(days=days)

    greeting_ok = (
        billing.has_feature(owner.id, "business_greeting")
        and _bool(row.greeting_enabled)
        and (row.greeting_text or "").strip()
        and (first_contact or inactive)
    )
    if greeting_ok:
        prev = _last_auto(db, owner.id, sender_id, "greeting")
        if prev is None or prev.sent_at is None or prev.sent_at <= now - timedelta(days=days):
            sent.append(
                _insert_auto_text(db, conv.id, owner.id, row.greeting_text.strip())
            )
            _mark_auto(db, owner.id, sender_id, "greeting")
            conv.updated_at = now
            return sent

    away_ok = (
        billing.has_feature(owner.id, "business_away")
        and _bool(row.away_enabled)
        and (row.away_text or "").strip()
    )
    if away_ok:
        mode = row.away_mode if row.away_mode in AWAY_MODES else "manual"
        if mode == "outside_hours":
            if not billing.has_feature(owner.id, "business_hours"):
                away_ok = False
            elif is_open_now(hours_from_row(row), now):
                away_ok = False
    if away_ok:
        prev = _last_auto(db, owner.id, sender_id, "away")
        if prev is None or prev.sent_at is None or prev.sent_at <= now - AWAY_COOLDOWN:
            sent.append(_insert_auto_text(db, conv.id, owner.id, row.away_text.strip()))
            _mark_auto(db, owner.id, sender_id, "away")
            conv.updated_at = now
    return sent
