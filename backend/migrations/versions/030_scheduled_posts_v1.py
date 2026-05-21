"""Scheduled posts + creator V1

Revision ID: 030_scheduled_posts_v1
Revises: 029_subscriptions_tiers_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "030_scheduled_posts_v1"
down_revision = "029_subscriptions_tiers_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "posts",
        sa.Column("scheduled_publish_at", sa.DateTime(), nullable=True),
    )
    op.create_index(
        "ix_posts_scheduled_publish_at",
        "posts",
        ["scheduled_publish_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_posts_scheduled_publish_at", table_name="posts")
    op.drop_column("posts", "scheduled_publish_at")
