"""Parse/encode chat location payloads (static + live)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

ALLOWED_LIVE_PERIODS = frozenset({900, 3600, 28800})
MIN_UPDATE_INTERVAL_SECONDS = 15


def _parse_bool(raw: str) -> bool:
    value = raw.strip().lower()
    return value in {"1", "true", "yes", "on"}


def parse_location_content(content: str) -> Optional[dict[str, Any]]:
    lines = [line.strip() for line in (content or "").split("\n") if line.strip()]
    if not lines:
        return None
    head = lines[0].lower()
    if "геопозиц" not in head and head not in {"han_location", "location"}:
        return None

    lat: Optional[float] = None
    lng: Optional[float] = None
    label: Optional[str] = None
    is_live = False
    period: Optional[int] = None
    expires_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    stopped = False

    for line in lines[1:]:
        lower = line.lower()
        if lower.startswith("lat:") or lower.startswith("latitude:"):
            lat = float(line.split(":", 1)[1].strip())
            continue
        if lower.startswith(("lng:", "lon:", "longitude:")):
            lng = float(line.split(":", 1)[1].strip())
            continue
        if lower.startswith("live:"):
            is_live = _parse_bool(line.split(":", 1)[1])
            continue
        if lower.startswith("period:"):
            period = int(float(line.split(":", 1)[1].strip()))
            continue
        if lower.startswith("expires_at:"):
            expires_at = _parse_iso(line.split(":", 1)[1].strip())
            continue
        if lower.startswith("updated_at:"):
            updated_at = _parse_iso(line.split(":", 1)[1].strip())
            continue
        if lower.startswith("stopped:"):
            stopped = _parse_bool(line.split(":", 1)[1])
            continue
        if label is None:
            label = line

    if lat is None or lng is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    return {
        "latitude": lat,
        "longitude": lng,
        "label": label,
        "is_live": is_live,
        "period_seconds": period,
        "expires_at": expires_at,
        "updated_at": updated_at,
        "stopped": stopped,
    }


def _parse_iso(raw: str) -> Optional[datetime]:
    text = raw.strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _fmt_iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def encode_location_content(
    *,
    latitude: float,
    longitude: float,
    label: Optional[str] = None,
    is_live: bool = False,
    period_seconds: Optional[int] = None,
    expires_at: Optional[datetime] = None,
    updated_at: Optional[datetime] = None,
    stopped: bool = False,
) -> str:
    lines = [
        "📍 Геопозиция",
        f"lat: {latitude:.6f}",
        f"lng: {longitude:.6f}",
    ]
    if is_live:
        lines.append("live: 1")
        if period_seconds is not None:
            lines.append(f"period: {int(period_seconds)}")
        if expires_at is not None:
            lines.append(f"expires_at: {_fmt_iso(expires_at)}")
        if updated_at is not None:
            lines.append(f"updated_at: {_fmt_iso(updated_at)}")
        lines.append(f"stopped: {'1' if stopped else '0'}")
    label_clean = (label or "").strip()
    if label_clean:
        lines.append(label_clean)
    return "\n".join(lines)


def build_live_location_content(
    *,
    latitude: float,
    longitude: float,
    period_seconds: int,
    now: Optional[datetime] = None,
) -> str:
    if period_seconds not in ALLOWED_LIVE_PERIODS:
        raise ValueError("invalid_live_period")
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise ValueError("invalid_coordinates")
    stamp = now or datetime.now(timezone.utc)
    expires = stamp + timedelta(seconds=period_seconds)
    return encode_location_content(
        latitude=latitude,
        longitude=longitude,
        is_live=True,
        period_seconds=period_seconds,
        expires_at=expires,
        updated_at=stamp,
        stopped=False,
    )


def is_live_active(parsed: dict[str, Any], *, now: Optional[datetime] = None) -> bool:
    if not parsed.get("is_live"):
        return False
    if parsed.get("stopped"):
        return False
    expires = parsed.get("expires_at")
    if expires is None:
        return False
    stamp = now or datetime.now(timezone.utc)
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return expires > stamp


def update_live_location_content(
    content: str,
    *,
    latitude: float,
    longitude: float,
    now: Optional[datetime] = None,
) -> str:
    parsed = parse_location_content(content)
    if parsed is None or not parsed.get("is_live"):
        raise ValueError("not_live_location")
    if not is_live_active(parsed, now=now):
        raise ValueError("live_location_inactive")
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise ValueError("invalid_coordinates")

    stamp = now or datetime.now(timezone.utc)
    updated_at = parsed.get("updated_at")
    if updated_at is not None:
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        delta = (stamp - updated_at).total_seconds()
        if delta < MIN_UPDATE_INTERVAL_SECONDS:
            raise ValueError("live_location_rate_limited")

    return encode_location_content(
        latitude=latitude,
        longitude=longitude,
        label=parsed.get("label"),
        is_live=True,
        period_seconds=parsed.get("period_seconds"),
        expires_at=parsed.get("expires_at"),
        updated_at=stamp,
        stopped=False,
    )


def stop_live_location_content(
    content: str,
    *,
    now: Optional[datetime] = None,
) -> str:
    parsed = parse_location_content(content)
    if parsed is None or not parsed.get("is_live"):
        raise ValueError("not_live_location")
    if parsed.get("stopped"):
        return content
    stamp = now or datetime.now(timezone.utc)
    return encode_location_content(
        latitude=parsed["latitude"],
        longitude=parsed["longitude"],
        label=parsed.get("label"),
        is_live=True,
        period_seconds=parsed.get("period_seconds"),
        expires_at=parsed.get("expires_at"),
        updated_at=stamp,
        stopped=True,
    )
