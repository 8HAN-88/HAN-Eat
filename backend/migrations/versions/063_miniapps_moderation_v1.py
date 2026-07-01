"""miniapps moderation status v1

Revision ID: 063_miniapps_moderation_v1
Revises: 062_bot_miniapps_platform_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "063_miniapps_moderation_v1"
down_revision = "062_bot_miniapps_platform_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "bot_miniapps",
        sa.Column(
            "moderation_status",
            sa.String(length=16),
            nullable=False,
            server_default="pending",
        ),
    )
    op.add_column(
        "bot_miniapps",
        sa.Column("moderation_note", sa.String(length=512), nullable=True),
    )
    op.execute(
        "UPDATE bot_miniapps SET moderation_status = 'approved' "
        "WHERE is_builtin = TRUE OR is_official = TRUE"
    )


def downgrade() -> None:
    op.drop_column("bot_miniapps", "moderation_note")
    op.drop_column("bot_miniapps", "moderation_status")
