"""Telegram-like media spoiler flag on messages

Revision ID: 112_message_has_spoiler_v1
Revises: 111_group_admin_rights_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "112_message_has_spoiler_v1"
down_revision = "111_group_admin_rights_v1"
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


def _add_bool(table: str, column: str) -> None:
    if not _column_exists(table, column):
        op.add_column(
            table,
            sa.Column(
                column,
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )


def upgrade() -> None:
    if _table_exists("messages"):
        _add_bool("messages", "has_spoiler")
    if _table_exists("scheduled_messages"):
        _add_bool("scheduled_messages", "has_spoiler")


def downgrade() -> None:
    pass
