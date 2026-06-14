"""Channel member inbox prefs (archive, show in feed)

Revision ID: 055_channel_member_inbox_prefs
Revises: 054_chat_folder_filters
"""
from alembic import op
import sqlalchemy as sa

revision = "055_channel_member_inbox_prefs"
down_revision = "054_chat_folder_filters"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "channel_members",
        sa.Column("inbox_archived", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "channel_members",
        sa.Column("show_in_feed", sa.Boolean(), nullable=False, server_default="true"),
    )


def downgrade() -> None:
    op.drop_column("channel_members", "show_in_feed")
    op.drop_column("channel_members", "inbox_archived")
