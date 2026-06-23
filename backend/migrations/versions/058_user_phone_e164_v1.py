"""Store phone E.164 for account owner display

Revision ID: 058_user_phone_e164_v1
Revises: 057_video_mp4_1080p_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "058_user_phone_e164_v1"
down_revision = "057_video_mp4_1080p_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("phone_e164", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "phone_e164")
