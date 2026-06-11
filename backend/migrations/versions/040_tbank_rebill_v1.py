"""T-Bank recurring: RebillId for SBP/card autopayments

Revision ID: 040_tbank_rebill_v1
Revises: 039_legal_consent_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "040_tbank_rebill_v1"
down_revision = "039_legal_consent_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("tbank_rebill_id", sa.String(64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "tbank_rebill_id")
