"""Channel member join status (active / pending)

Revision ID: 035_channel_member_status_v1
Revises: 034_recipe_visibility_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "035_channel_member_status_v1"
down_revision = "034_recipe_visibility_v1"
branch_labels = None
depends_on = None

MEMBER_STATUS_ACTIVE = "active"
MEMBER_STATUS_PENDING = "pending"


def upgrade() -> None:
    op.add_column(
        "channel_members",
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=MEMBER_STATUS_ACTIVE,
        ),
    )
    op.create_index("ix_channel_members_status", "channel_members", ["status"])
    op.execute(
        f"UPDATE channel_members SET status = '{MEMBER_STATUS_ACTIVE}' WHERE status IS NULL"
    )


def downgrade() -> None:
    op.drop_index("ix_channel_members_status", table_name="channel_members")
    op.drop_column("channel_members", "status")
