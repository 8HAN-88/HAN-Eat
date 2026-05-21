"""Add rating column to comments

Revision ID: 025_comment_rating
Revises: 024_auto_publish_reels
Create Date: 2026-05-08
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '025_comment_rating'
down_revision = '024_auto_publish_reels'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('comments', sa.Column('rating', sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column('comments', 'rating')

