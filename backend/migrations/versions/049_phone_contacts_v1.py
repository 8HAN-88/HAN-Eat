"""Phone hash for contact discovery (Telegram-style)

Revision ID: 049_phone_contacts_v1
Revises: 048_group_chats_archive
"""
from alembic import op
import sqlalchemy as sa

revision = "049_phone_contacts_v1"
down_revision = "048_group_chats_archive"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("phone_hash", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("phone_linked_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_users_phone_hash", "users", ["phone_hash"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_users_phone_hash", table_name="users")
    op.drop_column("users", "phone_linked_at")
    op.drop_column("users", "phone_hash")
