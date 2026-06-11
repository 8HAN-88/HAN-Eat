"""Add messages_enabled to notification preferences

Revision ID: 046_messages_enabled
Revises: 045_chat_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "046_messages_enabled"
down_revision = "045_chat_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "notification_preferences",
        sa.Column("messages_enabled", sa.Boolean(), nullable=False, server_default="true"),
    )


def downgrade() -> None:
    op.drop_column("notification_preferences", "messages_enabled")
