"""Clear exclusive Pro flags and restore recipe indexing

Revision ID: 043_remove_exclusive_pro_v1
Revises: 042_subscription_promises_v1
"""
from alembic import op

revision = "043_remove_exclusive_pro_v1"
down_revision = "042_subscription_promises_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE posts
        SET is_exclusive = false,
            is_indexed = is_global_visible
        WHERE is_exclusive = true
        """
    )


def downgrade() -> None:
    pass
