"""Referral codes, extra-ads opt-in, and revenue share ledger.

Revision ID: 133_revenue_share_v1
Revises: 132_ads_inventory_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "133_revenue_share_v1"
down_revision = "132_ads_inventory_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    users_cols = {c["name"] for c in inspector.get_columns("users")}
    if "referral_code" not in users_cols:
        op.add_column("users", sa.Column("referral_code", sa.String(length=16), nullable=True))
        op.create_index("ix_users_referral_code", "users", ["referral_code"], unique=True)
    if "referred_by_user_id" not in users_cols:
        op.add_column("users", sa.Column("referred_by_user_id", sa.Integer(), nullable=True))
        op.create_index("ix_users_referred_by_user_id", "users", ["referred_by_user_id"])
    if "referred_at" not in users_cols:
        op.add_column("users", sa.Column("referred_at", sa.DateTime(), nullable=True))
    if "extra_ads_enabled" not in users_cols:
        op.add_column(
            "users",
            sa.Column(
                "extra_ads_enabled",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )
    if "extra_ads_enabled_at" not in users_cols:
        op.add_column("users", sa.Column("extra_ads_enabled_at", sa.DateTime(), nullable=True))

    tables = set(inspector.get_table_names())
    if "revenue_share_ledger" not in tables:
        op.create_table(
            "revenue_share_ledger",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("beneficiary_user_id", sa.Integer(), nullable=False),
            sa.Column("role", sa.String(length=16), nullable=False),
            sa.Column("source", sa.String(length=20), nullable=False),
            sa.Column("subject_user_id", sa.Integer(), nullable=False),
            sa.Column("referrer_user_id", sa.Integer(), nullable=True),
            sa.Column("extra_ads", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("gross_kopecks", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("net_kopecks", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("share_kopecks", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
            sa.Column("available_at", sa.DateTime(), nullable=True),
            sa.Column("reference_type", sa.String(length=32), nullable=False),
            sa.Column("reference_id", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["beneficiary_user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["subject_user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["referrer_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.UniqueConstraint(
                "source",
                "reference_type",
                "reference_id",
                "role",
                name="uq_revenue_share_ref_role",
            ),
        )
        op.create_index(
            "ix_revenue_share_ledger_beneficiary_user_id",
            "revenue_share_ledger",
            ["beneficiary_user_id"],
        )
        op.create_index(
            "ix_revenue_share_ledger_subject_user_id",
            "revenue_share_ledger",
            ["subject_user_id"],
        )
        op.create_index(
            "ix_revenue_share_ledger_status",
            "revenue_share_ledger",
            ["status"],
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "revenue_share_ledger" in set(inspector.get_table_names()):
        op.drop_table("revenue_share_ledger")
    users_cols = {c["name"] for c in inspector.get_columns("users")}
    if "extra_ads_enabled_at" in users_cols:
        op.drop_column("users", "extra_ads_enabled_at")
    if "extra_ads_enabled" in users_cols:
        op.drop_column("users", "extra_ads_enabled")
    if "referred_at" in users_cols:
        op.drop_column("users", "referred_at")
    if "referred_by_user_id" in users_cols:
        op.drop_index("ix_users_referred_by_user_id", table_name="users")
        op.drop_column("users", "referred_by_user_id")
    if "referral_code" in users_cols:
        op.drop_index("ix_users_referral_code", table_name="users")
        op.drop_column("users", "referral_code")
