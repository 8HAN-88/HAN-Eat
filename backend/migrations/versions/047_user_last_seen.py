"""Add last_seen_at to users for chat presence

Revision ID: 047_user_last_seen
Revises: 046_messages_enabled
"""
from alembic import op
import sqlalchemy as sa

revision = "047_user_last_seen"
down_revision = "046_messages_enabled"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("last_seen_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "last_seen_at")
