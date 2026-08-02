"""users.voip_token for iOS PushKit / CallKit

Revision ID: 109_user_voip_token_v1
Revises: 108_call_sessions_v1
Create Date: 2026-08-02
"""

from alembic import op
import sqlalchemy as sa


revision = "109_user_voip_token_v1"
down_revision = "108_call_sessions_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("voip_token", sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "voip_token")
