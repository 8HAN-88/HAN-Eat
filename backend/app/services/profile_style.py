"""Telegram-like emoji status and profile name colors."""
from __future__ import annotations

from typing import Optional

PROFILE_COLORS = {
    "blue": "#3390EC",
    "red": "#E53935",
    "orange": "#FB8C00",
    "green": "#43A047",
    "cyan": "#00ACC1",
    "purple": "#8E24AA",
    "pink": "#D81B60",
    "navy": "#1565C0",
}


def normalize_emoji_status(raw: Optional[str]) -> Optional[str]:
    text = (raw or "").strip()
    if not text:
        return None
    return text[:8]


def normalize_profile_color(raw: Optional[str]) -> Optional[str]:
    key = (raw or "").strip().lower()
    if not key:
        return None
    if key not in PROFILE_COLORS:
        raise ValueError("bad_profile_color")
    return key


def profile_color_hex(key: Optional[str]) -> Optional[str]:
    if not key:
        return None
    return PROFILE_COLORS.get(str(key).strip().lower())
