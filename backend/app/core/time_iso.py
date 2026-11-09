"""UTC timestamps on the wire, including a Z for naive UTC values."""
from __future__ import annotations

from datetime import datetime, timezone


def utc_iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        text = value.isoformat()
        if text.endswith(("Z", "z")):
            return text
        return f"{text}Z"
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_search_bound(value: str | None, *, end_of_day: bool = False) -> datetime | None:
    """Naive UTC bound for a search day.

    ``YYYY-MM-DD`` stays a UTC calendar day (old clients). An ISO instant
    with ``Z`` or an offset is the phone's local midnight or end of day,
    stored the same way as ``created_at``.
    """
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    if len(text) == 10 and text[4] == "-" and text[7] == "-":
        parsed = datetime.strptime(text, "%Y-%m-%d")
        if end_of_day:
            return parsed.replace(hour=23, minute=59, second=59)
        return parsed
    iso = text[:-1] + "+00:00" if text.endswith(("Z", "z")) else text
    try:
        parsed = datetime.fromisoformat(iso)
    except ValueError as exc:
        raise ValueError("bad search date") from exc
    if parsed.tzinfo is None:
        return parsed
    return parsed.astimezone(timezone.utc).replace(tzinfo=None)
