"""Subscription promise fields: pin, exclusive, priority support, channel accent

Revision ID: 042_subscription_promises_v1
Revises: 041_channel_role_permissions_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "042_subscription_promises_v1"
down_revision = "041_channel_role_permissions_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "posts",
        sa.Column("is_pinned", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "posts",
        sa.Column("is_exclusive", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.create_index("ix_posts_is_pinned", "posts", ["is_pinned"])
    op.create_index("ix_posts_is_exclusive", "posts", ["is_exclusive"])

    op.add_column(
        "support_tickets",
        sa.Column("is_priority", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.create_index("ix_support_tickets_is_priority", "support_tickets", ["is_priority"])

    op.add_column(
        "channels",
        sa.Column("accent_color", sa.String(16), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("channels", "accent_color")
    op.drop_index("ix_support_tickets_is_priority", table_name="support_tickets")
    op.drop_column("support_tickets", "is_priority")
    op.drop_index("ix_posts_is_exclusive", table_name="posts")
    op.drop_index("ix_posts_is_pinned", table_name="posts")
    op.drop_column("posts", "is_exclusive")
    op.drop_column("posts", "is_pinned")
