"""Channel inbox: last_seen_posts_count on channel_members

Revision ID: 052_channel_inbox_seen
Revises: 051_chat_v2_1_messages
"""
from alembic import op
import sqlalchemy as sa

revision = "052_channel_inbox_seen"
down_revision = "051_chat_v2_1_messages"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "channel_members",
        sa.Column("last_seen_posts_count", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("channel_members", "last_seen_posts_count")
