"""Anonymous admin display helpers."""
import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.services.anonymous_admin import (
    can_send_anonymously,
    resolve_anonymous_sender_display,
)


def test_can_send_anonymously_only_group_admins():
    assert can_send_anonymously(is_group=True, is_admin=True) is True
    assert can_send_anonymously(is_group=True, is_admin=False) is False
    assert can_send_anonymously(is_group=False, is_admin=True) is False


def test_members_see_group_title_only():
    name, flag = resolve_anonymous_sender_display(
        is_anonymous=True,
        group_title="Team",
        real_sender_name="Alice",
        viewer_is_sender=False,
        viewer_is_admin=False,
    )
    assert flag is True
    assert name == "Team"


def test_admins_see_revealed_name():
    name, flag = resolve_anonymous_sender_display(
        is_anonymous=True,
        group_title="Team",
        real_sender_name="Alice",
        viewer_is_sender=False,
        viewer_is_admin=True,
    )
    assert flag is True
    assert name == "Team (Alice)"


def test_non_anonymous_passthrough():
    name, flag = resolve_anonymous_sender_display(
        is_anonymous=False,
        group_title="Team",
        real_sender_name="Alice",
        viewer_is_sender=False,
        viewer_is_admin=False,
    )
    assert flag is False
    assert name == "Alice"
