"""Paid group Stars, TON payout destination, gift display order.

Revision ID: 126_paid_groups_ton_gifts_v1
Revises: 124_gift_marketplace_wear_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "126_paid_groups_ton_gifts_v1"
down_revision = "124_gift_marketplace_wear_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(c["name"] == column_name for c in inspector.get_columns(table_name))


def upgrade() -> None:
    if _table_exists("conversations"):
        if not _column_exists("conversations", "is_paid"):
            op.add_column(
                "conversations",
                sa.Column(
                    "is_paid",
                    sa.Boolean(),
                    nullable=False,
                    server_default=sa.false(),
                ),
            )
        if not _column_exists("conversations", "monthly_price_stars"):
            op.add_column(
                "conversations",
                sa.Column(
                    "monthly_price_stars",
                    sa.Integer(),
                    nullable=False,
                    server_default="0",
                ),
            )

    if _table_exists("users") and not _column_exists("users", "ton_address"):
        op.add_column(
            "users",
            sa.Column("ton_address", sa.String(length=128), nullable=True),
        )

    if _table_exists("creator_payout_requests"):
        if not _column_exists("creator_payout_requests", "method"):
            op.add_column(
                "creator_payout_requests",
                sa.Column(
                    "method",
                    sa.String(length=16),
                    nullable=False,
                    server_default="rub",
                ),
            )
        if not _column_exists("creator_payout_requests", "ton_address"):
            op.add_column(
                "creator_payout_requests",
                sa.Column("ton_address", sa.String(length=128), nullable=True),
            )

    if _table_exists("user_star_gifts") and not _column_exists(
        "user_star_gifts", "display_order"
    ):
        op.add_column(
            "user_star_gifts",
            sa.Column(
                "display_order",
                sa.Integer(),
                nullable=False,
                server_default="0",
            ),
        )

    if not _table_exists("paid_group_subscriptions"):
        op.create_table(
            "paid_group_subscriptions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "conversation_id",
                sa.Integer(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("amount_stars", sa.Integer(), nullable=False),
            sa.Column(
                "status",
                sa.String(length=24),
                nullable=False,
                server_default="active",
            ),
            sa.Column(
                "started_at",
                sa.DateTime(),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column(
                "auto_renew",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
            sa.Column(
                "created_at",
                sa.DateTime(),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.UniqueConstraint(
                "user_id",
                "conversation_id",
                name="uq_paid_group_user_conversation",
            ),
        )
        op.create_index(
            "ix_paid_group_subscriptions_conversation_id",
            "paid_group_subscriptions",
            ["conversation_id"],
        )
        op.create_index(
            "ix_paid_group_subscriptions_status",
            "paid_group_subscriptions",
            ["status"],
        )


def downgrade() -> None:
    if _table_exists("paid_group_subscriptions"):
        op.drop_index(
            "ix_paid_group_subscriptions_status",
            table_name="paid_group_subscriptions",
        )
        op.drop_index(
            "ix_paid_group_subscriptions_conversation_id",
            table_name="paid_group_subscriptions",
        )
        op.drop_table("paid_group_subscriptions")
    if _table_exists("user_star_gifts") and _column_exists(
        "user_star_gifts", "display_order"
    ):
        op.drop_column("user_star_gifts", "display_order")
    if _table_exists("creator_payout_requests"):
        if _column_exists("creator_payout_requests", "ton_address"):
            op.drop_column("creator_payout_requests", "ton_address")
        if _column_exists("creator_payout_requests", "method"):
            op.drop_column("creator_payout_requests", "method")
    if _table_exists("users") and _column_exists("users", "ton_address"):
        op.drop_column("users", "ton_address")
    if _table_exists("conversations"):
        if _column_exists("conversations", "monthly_price_stars"):
            op.drop_column("conversations", "monthly_price_stars")
        if _column_exists("conversations", "is_paid"):
            op.drop_column("conversations", "is_paid")
