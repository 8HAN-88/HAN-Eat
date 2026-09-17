"""Partner payout requests and ledger hold/paid link.

Revision ID: 134_partner_payouts
Revises: 133_revenue_share_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "134_partner_payouts"
down_revision = "133_revenue_share_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "partner_payout_requests" not in tables:
        op.create_table(
            "partner_payout_requests",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("kind", sa.String(length=16), nullable=False),
            sa.Column("amount_kopecks", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("amount_stars", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
            sa.Column("phone", sa.String(length=20), nullable=True),
            sa.Column("recipient_name", sa.String(length=80), nullable=True),
            sa.Column("note", sa.String(length=512), nullable=True),
            sa.Column("reviewed_by_user_id", sa.Integer(), nullable=True),
            sa.Column("reviewed_at", sa.DateTime(), nullable=True),
            sa.Column("paid_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(
                ["reviewed_by_user_id"], ["users.id"], ondelete="SET NULL"
            ),
        )
        op.create_index(
            "ix_partner_payout_requests_user_id",
            "partner_payout_requests",
            ["user_id"],
        )
        op.create_index(
            "ix_partner_payout_requests_status",
            "partner_payout_requests",
            ["status"],
        )
        op.create_index(
            "ix_partner_payout_requests_kind",
            "partner_payout_requests",
            ["kind"],
        )

    if "revenue_share_ledger" in set(inspector.get_table_names()):
        cols = {c["name"] for c in inspector.get_columns("revenue_share_ledger")}
        if "payout_request_id" not in cols:
            op.add_column(
                "revenue_share_ledger",
                sa.Column("payout_request_id", sa.Integer(), nullable=True),
            )
            op.create_index(
                "ix_revenue_share_ledger_payout_request_id",
                "revenue_share_ledger",
                ["payout_request_id"],
            )
            op.create_foreign_key(
                "fk_revenue_share_ledger_payout_request_id",
                "revenue_share_ledger",
                "partner_payout_requests",
                ["payout_request_id"],
                ["id"],
                ondelete="SET NULL",
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "revenue_share_ledger" in set(inspector.get_table_names()):
        cols = {c["name"] for c in inspector.get_columns("revenue_share_ledger")}
        if "payout_request_id" in cols:
            op.drop_constraint(
                "fk_revenue_share_ledger_payout_request_id",
                "revenue_share_ledger",
                type_="foreignkey",
            )
            op.drop_index(
                "ix_revenue_share_ledger_payout_request_id",
                table_name="revenue_share_ledger",
            )
            op.drop_column("revenue_share_ledger", "payout_request_id")
    if "partner_payout_requests" in set(inspector.get_table_names()):
        op.drop_table("partner_payout_requests")
