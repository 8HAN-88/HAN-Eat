"""Group forums / topics

Revision ID: 119_group_forums_topics_v1
Revises: 118_message_effect_id_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "119_group_forums_topics_v1"
down_revision = "118_message_effect_id_v1"
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
    if _table_exists("conversations") and not _column_exists("conversations", "is_forum"):
        op.add_column(
            "conversations",
            sa.Column(
                "is_forum",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )

    if not _table_exists("forum_topics"):
        op.create_table(
            "forum_topics",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("conversation_id", sa.Integer(), nullable=False),
            sa.Column("title", sa.String(length=128), nullable=False),
            sa.Column("icon_emoji", sa.String(length=16), nullable=True),
            sa.Column("created_by_user_id", sa.Integer(), nullable=True),
            sa.Column(
                "is_general",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
            sa.Column("closed_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.ForeignKeyConstraint(
                ["conversation_id"], ["conversations.id"], ondelete="CASCADE"
            ),
            sa.ForeignKeyConstraint(
                ["created_by_user_id"], ["users.id"], ondelete="SET NULL"
            ),
        )
        op.create_index(
            "ix_forum_topics_conversation_id", "forum_topics", ["conversation_id"]
        )

    if _table_exists("messages") and not _column_exists("messages", "topic_id"):
        op.add_column(
            "messages",
            sa.Column("topic_id", sa.Integer(), nullable=True),
        )
        op.create_foreign_key(
            "fk_messages_topic_id",
            "messages",
            "forum_topics",
            ["topic_id"],
            ["id"],
            ondelete="SET NULL",
        )
        op.create_index(
            "ix_messages_conversation_topic_id",
            "messages",
            ["conversation_id", "topic_id", "id"],
        )


def downgrade() -> None:
    pass
