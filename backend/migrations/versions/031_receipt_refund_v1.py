"""Receipt URL and refund status on subscriptions

Revision ID: 031_receipt_refund_v1
Revises: 030_scheduled_posts_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "031_receipt_refund_v1"
down_revision = "030_scheduled_posts_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "subscriptions",
        sa.Column("receipt_url", sa.String(512), nullable=True),
    )
    op.add_column(
        "subscriptions",
        sa.Column(
            "refund_status",
            sa.String(20),
            nullable=False,
            server_default="none",
        ),
    )
    op.add_column(
        "subscriptions",
        sa.Column("refunded_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("subscriptions", "refunded_at")
    op.drop_column("subscriptions", "refund_status")
    op.drop_column("subscriptions", "receipt_url")
