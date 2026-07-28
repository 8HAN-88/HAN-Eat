"""messages + scheduled_messages.media_group_id

Revision ID: 097_media_group_id_v1
Revises: 096_scheduled_silent_disable_preview_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "097_media_group_id_v1"
down_revision = "096_scheduled_silent_disable_preview_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def _indexes(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {idx["name"] for idx in inspector.get_indexes(table)}


def upgrade() -> None:
    msg_cols = _columns("messages")
    if "media_group_id" not in msg_cols:
        op.add_column(
            "messages",
            sa.Column("media_group_id", sa.String(length=64), nullable=True),
        )
    msg_indexes = _indexes("messages")
    if "ix_messages_conversation_media_group" not in msg_indexes:
        op.create_index(
            "ix_messages_conversation_media_group",
            "messages",
            ["conversation_id", "media_group_id"],
        )

    sched_cols = _columns("scheduled_messages")
    if "media_group_id" not in sched_cols:
        op.add_column(
            "scheduled_messages",
            sa.Column("media_group_id", sa.String(length=64), nullable=True),
        )


def downgrade() -> None:
    msg_indexes = _indexes("messages")
    if "ix_messages_conversation_media_group" in msg_indexes:
        op.drop_index(
            "ix_messages_conversation_media_group", table_name="messages"
        )
    msg_cols = _columns("messages")
    if "media_group_id" in msg_cols:
        op.drop_column("messages", "media_group_id")

    sched_cols = _columns("scheduled_messages")
    if "media_group_id" in sched_cols:
        op.drop_column("scheduled_messages", "media_group_id")
