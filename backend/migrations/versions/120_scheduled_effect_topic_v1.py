"""Scheduled messages: effect_id + topic_id

Revision ID: 120_scheduled_effect_topic_v1
Revises: 119_group_forums_topics_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "120_scheduled_effect_topic_v1"
down_revision = "119_group_forums_topics_v1"
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
    if not _table_exists("scheduled_messages"):
        return
    if not _column_exists("scheduled_messages", "effect_id"):
        op.add_column(
            "scheduled_messages",
            sa.Column("effect_id", sa.String(length=32), nullable=True),
        )
    if not _column_exists("scheduled_messages", "topic_id"):
        op.add_column(
            "scheduled_messages",
            sa.Column("topic_id", sa.Integer(), nullable=True),
        )
        if _table_exists("forum_topics"):
            op.create_foreign_key(
                "fk_scheduled_messages_topic_id",
                "scheduled_messages",
                "forum_topics",
                ["topic_id"],
                ["id"],
                ondelete="SET NULL",
            )


def downgrade() -> None:
    pass
