"""Granular Telegram-like group admin rights

Revision ID: 111_group_admin_rights_v1
Revises: 110_group_call_participants_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "111_group_admin_rights_v1"
down_revision = "110_group_call_participants_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(col.get("name") == column_name for col in inspector.get_columns(table_name))


def _add_bool_column_if_missing(table_name: str, column_name: str) -> None:
    if not _column_exists(table_name, column_name):
        op.add_column(
            table_name,
            sa.Column(
                column_name,
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )


def upgrade() -> None:
    if not _table_exists("conversation_members"):
        return
    for col in (
        "can_change_info",
        "can_delete_messages",
        "can_pin_messages",
        "can_invite_users",
        "can_manage_video_chats",
    ):
        _add_bool_column_if_missing("conversation_members", col)

    # Existing admins keep full rights after rollout (no sudden lockout).
    op.execute(
        """
        UPDATE conversation_members
        SET can_change_info = true,
            can_delete_messages = true,
            can_pin_messages = true,
            can_invite_users = true,
            can_manage_video_chats = true
        WHERE is_admin = true
        """
    )


def downgrade() -> None:
    # Keep downgrade conservative on production data.
    pass
