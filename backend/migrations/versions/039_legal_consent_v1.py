"""Legal consent (privacy + terms) versioning

Revision ID: 039_legal_consent_v1
Revises: 038_sbp_recurring_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "039_legal_consent_v1"
down_revision = "038_sbp_recurring_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("legal_consent_version", sa.String(32), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("legal_consent_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "legal_consent_at")
    op.drop_column("users", "legal_consent_version")
