"""creator payout requests table

Revision ID: 067_creator_payout_requests_v1
Revises: 066_bot_users_base_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "067_creator_payout_requests_v1"
down_revision = "066_bot_users_base_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _index_exists(table_name: str, index_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(idx.get("name") == index_name for idx in inspector.get_indexes(table_name))


def upgrade() -> None:
    if not _table_exists("creator_payout_requests"):
        op.create_table(
            "creator_payout_requests",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column(
                "creator_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("amount_stars", sa.Integer(), nullable=False),
            sa.Column("amount_rub", sa.Numeric(12, 2), nullable=False),
            sa.Column("status", sa.String(length=24), nullable=False, server_default="pending"),
            sa.Column("note", sa.String(length=512), nullable=True),
            sa.Column(
                "reviewed_by_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("reviewed_at", sa.DateTime(), nullable=True),
            sa.Column("paid_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
            sa.PrimaryKeyConstraint("id"),
        )

    if not _index_exists("creator_payout_requests", "ix_creator_payout_requests_id"):
        op.create_index(
            "ix_creator_payout_requests_id",
            "creator_payout_requests",
            ["id"],
            unique=False,
        )
    if not _index_exists("creator_payout_requests", "ix_creator_payout_requests_creator_user_id"):
        op.create_index(
            "ix_creator_payout_requests_creator_user_id",
            "creator_payout_requests",
            ["creator_user_id"],
            unique=False,
        )
    if not _index_exists("creator_payout_requests", "ix_creator_payout_requests_status"):
        op.create_index(
            "ix_creator_payout_requests_status",
            "creator_payout_requests",
            ["status"],
            unique=False,
        )
    if not _index_exists("creator_payout_requests", "ix_creator_payout_requests_reviewed_by_user_id"):
        op.create_index(
            "ix_creator_payout_requests_reviewed_by_user_id",
            "creator_payout_requests",
            ["reviewed_by_user_id"],
            unique=False,
        )
    if not _index_exists("creator_payout_requests", "ix_creator_payout_requests_created_at"):
        op.create_index(
            "ix_creator_payout_requests_created_at",
            "creator_payout_requests",
            ["created_at"],
            unique=False,
        )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
