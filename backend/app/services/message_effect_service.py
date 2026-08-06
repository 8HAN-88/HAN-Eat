"""Whitelist helpers for Telegram-like message send effects."""
from __future__ import annotations

from typing import Optional

MESSAGE_EFFECT_IDS = frozenset(
    {
        "confetti",
        "fireworks",
        "hearts",
        "celebration",
        "thumbs_up",
    }
)


def normalize_effect_id(raw: Optional[str]) -> Optional[str]:
    if raw is None:
        return None
    value = str(raw).strip().lower()[:32]
    if not value:
        return None
    if value not in MESSAGE_EFFECT_IDS:
        raise ValueError("effect_id_invalid")
    return value
