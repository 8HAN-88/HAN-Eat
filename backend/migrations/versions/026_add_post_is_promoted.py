"""Add is_promoted to posts for feed ranking

Revision ID: 026_post_is_promoted
Revises: 025_comment_rating
Create Date: 2026-05-11
"""
from alembic import op
import sqlalchemy as sa


revision = "026_post_is_promoted"
down_revision = "025_comment_rating"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "posts",
        sa.Column(
            "is_promoted",
            sa.Boolean(),
            nullable=False,
            server_default="false",
        ),
    )
    op.create_index("ix_posts_is_promoted", "posts", ["is_promoted"])


def downgrade() -> None:
    op.drop_index("ix_posts_is_promoted", table_name="posts")
    op.drop_column("posts", "is_promoted")
