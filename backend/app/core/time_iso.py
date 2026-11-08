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
