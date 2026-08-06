"""Message effect_id for Telegram-like send effects

Revision ID: 118_message_effect_id_v1
Revises: 117_bot_reply_keyboard_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "118_message_effect_id_v1"
down_revision = "117_bot_reply_keyboard_v1"
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


def upgrade() -> None:
    if not _table_exists("messages"):
        return
    if not _column_exists("messages", "effect_id"):
        op.add_column(
            "messages",
            sa.Column("effect_id", sa.String(length=32), nullable=True),
        )


def downgrade() -> None:
    if _table_exists("messages") and _column_exists("messages", "effect_id"):
        op.drop_column("messages", "effect_id")
