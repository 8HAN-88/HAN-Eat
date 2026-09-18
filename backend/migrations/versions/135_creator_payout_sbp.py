"""Creator payout SBP phone and recipient name.

Revision ID: 135_creator_payout_sbp
Revises: 134_partner_payouts
"""

from alembic import op
import sqlalchemy as sa


revision = "135_creator_payout_sbp"
down_revision = "134_partner_payouts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "creator_payout_requests" not in set(inspector.get_table_names()):
        return
    columns = {col["name"] for col in inspector.get_columns("creator_payout_requests")}
    if "phone" not in columns:
        op.add_column(
            "creator_payout_requests",
            sa.Column("phone", sa.String(length=32), nullable=True),
        )
    if "recipient_name" not in columns:
        op.add_column(
            "creator_payout_requests",
            sa.Column("recipient_name", sa.String(length=80), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "creator_payout_requests" not in set(inspector.get_table_names()):
        return
    columns = {col["name"] for col in inspector.get_columns("creator_payout_requests")}
    if "recipient_name" in columns:
        op.drop_column("creator_payout_requests", "recipient_name")
    if "phone" in columns:
        op.drop_column("creator_payout_requests", "phone")
