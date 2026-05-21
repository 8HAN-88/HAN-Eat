"""AI scan credits (soft limits)

Revision ID: 027_ai_scan_credits
Revises: 026_post_is_promoted
Create Date: 2026-05-14
"""
from alembic import op
import sqlalchemy as sa


revision = "027_ai_scan_credits"
down_revision = "026_post_is_promoted"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "scan_credits",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
    )
    op.add_column(
        "users",
        sa.Column(
            "last_scan_credit_at",
            sa.DateTime(timezone=False),
            nullable=True,
        ),
    )
    op.execute(
        "UPDATE users SET last_scan_credit_at = COALESCE(created_at, NOW()) "
        "WHERE last_scan_credit_at IS NULL"
    )


def downgrade() -> None:
    op.drop_column("users", "last_scan_credit_at")
    op.drop_column("users", "scan_credits")
