"""scheduled chat messages table

Revision ID: 068_scheduled_chat_messages_v1
Revises: 067_creator_payout_requests_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "068_scheduled_chat_messages_v1"
down_revision = "067_creator_payout_requests_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _index_exists(table_name: str, index_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(idx.get("name") == index_name for idx in inspector.get_indexes(table_name))


def upgrade() -> None:
    if not _table_exists("scheduled_messages"):
        op.create_table(
            "scheduled_messages",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column(
                "conversation_id",
                sa.Integer(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "sender_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("type", sa.String(length=20), nullable=False, server_default="text"),
            sa.Column("content", sa.String(length=4000), nullable=False, server_default=""),
            sa.Column("media_url", sa.String(length=512), nullable=True),
            sa.Column(
                "reply_to_message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("client_message_id", sa.String(length=64), nullable=True),
            sa.Column("inline_keyboard_json", sa.String(length=4000), nullable=True),
            sa.Column("send_at", sa.DateTime(), nullable=False),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
            sa.Column(
                "sent_message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("sent_at", sa.DateTime(), nullable=True),
            sa.Column("error_text", sa.String(length=120), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
            sa.Column("canceled_at", sa.DateTime(), nullable=True),
            sa.PrimaryKeyConstraint("id"),
        )

    for idx in (
        "ix_scheduled_messages_id",
        "ix_scheduled_messages_conversation_id",
        "ix_scheduled_messages_sender_id",
        "ix_scheduled_messages_send_at",
        "ix_scheduled_messages_status",
        "ix_scheduled_messages_created_at",
    ):
        if _index_exists("scheduled_messages", idx):
            continue
        column = idx.replace("ix_scheduled_messages_", "")
        op.create_index(idx, "scheduled_messages", [column], unique=False)


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
