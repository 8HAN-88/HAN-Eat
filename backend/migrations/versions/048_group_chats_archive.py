"""Group chats title + per-user archive

Revision ID: 048_group_chats_archive
Revises: 047_user_last_seen
"""
from alembic import op
import sqlalchemy as sa

revision = "048_group_chats_archive"
down_revision = "047_user_last_seen"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "conversations",
        sa.Column("title", sa.String(length=120), nullable=True),
    )
    op.add_column(
        "conversations",
        sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "conversation_members",
        sa.Column("archived_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("conversation_members", "archived_at")
    op.drop_column("conversations", "created_by_user_id")
    op.drop_column("conversations", "title")
