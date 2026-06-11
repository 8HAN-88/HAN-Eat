"""SBP recurring: saved payment method and pending renewal

Revision ID: 038_sbp_recurring_v1
Revises: 037_post_poll_votes_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "038_sbp_recurring_v1"
down_revision = "037_post_poll_votes_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("yookassa_payment_method_id", sa.String(64), nullable=True),
    )
    op.add_column(
        "subscriptions",
        sa.Column("pending_renewal_payment_id", sa.String(64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("subscriptions", "pending_renewal_payment_id")
    op.drop_column("users", "yookassa_payment_method_id")
