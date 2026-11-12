"""Short quote shown on a reply when the original message is not loaded."""

from __future__ import annotations

_TYPE_LABELS = {
    "voice": "Голосовое сообщение",
    "image": "Фото",
    "video": "Видео",
    "video_note": "Видеосообщение",
    "sticker": "Стикер",
    "poll": "Опрос",
    "location": "Геопозиция",
    "live_location": "Геопозиция",
    "gift": "Подарок",
    "stars_tip": "Звёзды",
    "call": "Звонок",
    "story_reply": "Ответ на сторис",
    "file": "Файл",
}


def reply_preview_text(
    msg_type: str | None,
    content: str | None,
    *,
    deleted: bool = False,
) -> str:
    if deleted:
        return "Сообщение удалено"
    kind = (msg_type or "text").strip() or "text"
    raw = (content or "").strip()
    if kind == "file":
        name = raw.splitlines()[0].strip() if raw else ""
        return (name or "Файл")[:80]
    if kind == "text":
        if not raw:
            return "Сообщение"
        first = raw.splitlines()[0].strip().lower()
        if (
            first in {"han_contact", "👤 контакт"}
            or first.startswith("👤")
            or first.startswith("контакт")
        ):
            return "Контакт"
        text = " ".join(raw.split())
        return text[:120] or "Сообщение"
    return _TYPE_LABELS.get(kind, "Сообщение")
