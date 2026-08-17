"""Flexible leveled subscription catalog and user layouts.

Revision ID: 127_flex_subscription_v1
Revises: 126_paid_groups_ton_gifts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "127_flex_subscription_v1"
down_revision = "126_paid_groups_ton_gifts_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if not _table_exists("subscription_feature_blocks"):
        op.create_table(
            "subscription_feature_blocks",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("key", sa.String(length=32), nullable=False),
            sa.Column("title", sa.String(length=120), nullable=False),
            sa.Column("min_level", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("max_level", sa.Integer(), nullable=False, server_default="3"),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("key", name="uq_subscription_feature_blocks_key"),
        )
        op.create_index(
            "ix_subscription_feature_blocks_key",
            "subscription_feature_blocks",
            ["key"],
        )

    if not _table_exists("subscription_features"):
        op.create_table(
            "subscription_features",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("slug", sa.String(length=64), nullable=False),
            sa.Column("title", sa.String(length=160), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("icon", sa.String(length=64), nullable=True),
            sa.Column("price_rub", sa.Numeric(10, 2), nullable=True),
            sa.Column("min_level", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("max_level", sa.Integer(), nullable=False, server_default="10"),
            sa.Column("default_level", sa.Integer(), nullable=False, server_default="1"),
            sa.Column(
                "feature_type",
                sa.String(length=16),
                nullable=False,
                server_default="movable",
            ),
            sa.Column("movable", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("required", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("block_key", sa.String(length=32), nullable=True),
            sa.Column("launch_at", sa.DateTime(), nullable=True),
            sa.Column(
                "status",
                sa.String(length=16),
                nullable=False,
                server_default="active",
            ),
            sa.Column("available", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("slug", name="uq_subscription_features_slug"),
        )
        op.create_index("ix_subscription_features_slug", "subscription_features", ["slug"])
        op.create_index("ix_subscription_features_status", "subscription_features", ["status"])
        op.create_index(
            "ix_subscription_features_block_key",
            "subscription_features",
            ["block_key"],
        )

    if not _table_exists("user_flex_subscriptions"):
        op.create_table(
            "user_flex_subscriptions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("current_level", sa.Integer(), nullable=False, server_default="0"),
            sa.Column(
                "status",
                sa.String(length=20),
                nullable=False,
                server_default="inactive",
            ),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("payment_subscription_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("user_id", name="uq_user_flex_subscriptions_user"),
        )
        op.create_index(
            "ix_user_flex_subscriptions_user_id",
            "user_flex_subscriptions",
            ["user_id"],
        )
        op.create_index(
            "ix_user_flex_subscriptions_status",
            "user_flex_subscriptions",
            ["status"],
        )

    if not _table_exists("user_flex_slots"):
        op.create_table(
            "user_flex_slots",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "feature_id",
                sa.Integer(),
                sa.ForeignKey("subscription_features.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("assigned_level", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("user_id", "feature_id", name="uq_flex_slot_user_feature"),
            sa.UniqueConstraint("user_id", "assigned_level", name="uq_flex_slot_user_level"),
        )
        op.create_index("ix_user_flex_slots_user_id", "user_flex_slots", ["user_id"])
        op.create_index("ix_user_flex_slots_feature_id", "user_flex_slots", ["feature_id"])


def downgrade() -> None:
    if _table_exists("user_flex_slots"):
        op.drop_table("user_flex_slots")
    if _table_exists("user_flex_subscriptions"):
        op.drop_table("user_flex_subscriptions")
    if _table_exists("subscription_features"):
        op.drop_table("subscription_features")
    if _table_exists("subscription_feature_blocks"):
        op.drop_table("subscription_feature_blocks")
