"""Allow several Flex features on the same subscription level.

Revision ID: 128_flex_multi_features_level_v1
Revises: 127_flex_subscription_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "128_flex_multi_features_level_v1"
down_revision = "127_flex_subscription_v1"
branch_labels = None
depends_on = None


def _has_unique(table_name: str, constraint_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(
        item.get("name") == constraint_name
        for item in inspector.get_unique_constraints(table_name)
    )


def upgrade() -> None:
    if _has_unique("user_flex_slots", "uq_flex_slot_user_level"):
        op.drop_constraint(
            "uq_flex_slot_user_level",
            "user_flex_slots",
            type_="unique",
        )
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "user_flex_slots" in inspector.get_table_names():
        existing = {item["name"] for item in inspector.get_indexes("user_flex_slots")}
        if "ix_user_flex_slots_user_level" not in existing:
            op.create_index(
                "ix_user_flex_slots_user_level",
                "user_flex_slots",
                ["user_id", "assigned_level"],
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "user_flex_slots" not in inspector.get_table_names():
        return
    existing = {item["name"] for item in inspector.get_indexes("user_flex_slots")}
    if "ix_user_flex_slots_user_level" in existing:
        op.drop_index("ix_user_flex_slots_user_level", table_name="user_flex_slots")
    if not _has_unique("user_flex_slots", "uq_flex_slot_user_level"):
        op.create_unique_constraint(
            "uq_flex_slot_user_level",
            "user_flex_slots",
            ["user_id", "assigned_level"],
        )
