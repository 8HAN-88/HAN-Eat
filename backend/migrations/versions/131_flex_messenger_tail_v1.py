"""Restore the long Flex messenger+ tail (levels 19–79).

Revision ID: 131_flex_messenger_tail_v1
Revises: 130_flex_long_ladder_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "131_flex_messenger_tail_v1"
down_revision = "130_flex_long_ladder_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "subscription_feature_blocks" not in inspector.get_table_names():
        return
    bind.execute(
        sa.text(
            "UPDATE subscription_feature_blocks "
            "SET title = 'PRO', min_level = 10, max_level = 18, sort_order = 3 "
            "WHERE key = 'C'"
        )
    )


def downgrade() -> None:
    return
