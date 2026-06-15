"""Add mp4_1080p_url to video_processing

Revision ID: 057_video_mp4_1080p_v1
Revises: 056_message_poll_votes_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "057_video_mp4_1080p_v1"
down_revision = "056_message_poll_votes_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "video_processing",
        sa.Column("mp4_1080p_url", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("video_processing", "mp4_1080p_url")
