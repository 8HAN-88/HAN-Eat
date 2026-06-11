"""Channel role permissions

Revision ID: 041_channel_role_permissions_v1
Revises: 040_tbank_rebill_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "041_channel_role_permissions_v1"
down_revision = "040_tbank_rebill_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "channels",
        sa.Column("role_permissions", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("channels", "role_permissions")
