"""add last_delivered_message_id for Telegram-like receipts

Revision ID: 083_chat_delivered_receipts_v1
Revises: 082_stickers_order_index_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "083_chat_delivered_receipts_v1"
down_revision = "082_stickers_order_index_v1"
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
    if _table_exists("conversation_members") and not _column_exists(
        "conversation_members", "last_delivered_message_id"
    ):
        op.add_column(
            "conversation_members",
            sa.Column("last_delivered_message_id", sa.Integer(), nullable=True),
        )


def downgrade() -> None:
    if _table_exists("conversation_members") and _column_exists(
        "conversation_members", "last_delivered_message_id"
    ):
        op.drop_column("conversation_members", "last_delivered_message_id")
