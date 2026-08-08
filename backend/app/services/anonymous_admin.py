"""Telegram-like anonymous admin posting helpers."""

from __future__ import annotations

from typing import Optional, Tuple


def resolve_anonymous_sender_display(
    *,
    is_anonymous: bool,
    group_title: Optional[str],
    real_sender_name: Optional[str],
    viewer_is_sender: bool,
    viewer_is_admin: bool,
) -> Tuple[Optional[str], bool]:
    """
    Returns (display_name, is_anonymous_flag_for_client).

    Members see the group title. Sender/admins see "Title (Real Name)".
    """
    if not is_anonymous:
        return real_sender_name, False
    title = (group_title or "").strip() or "Группа"
    if viewer_is_sender or viewer_is_admin:
        real = (real_sender_name or "").strip() or "Админ"
        return f"{title} ({real})", True
    return title, True


def can_send_anonymously(*, is_group: bool, is_admin: bool) -> bool:
    return bool(is_group and is_admin)
