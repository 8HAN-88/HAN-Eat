"""Chat folders (Telegram-style)

Revision ID: 053_chat_folders
Revises: 052_channel_inbox_seen
"""
from alembic import op
import sqlalchemy as sa

revision = "053_chat_folders"
down_revision = "052_channel_inbox_seen"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "chat_folders",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("icon", sa.String(length=8), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
    )
    op.create_index("ix_chat_folders_user_id", "chat_folders", ["user_id"])

    op.create_table(
        "chat_folder_items",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "folder_id",
            sa.Integer(),
            sa.ForeignKey("chat_folders.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "conversation_id",
            sa.Integer(),
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column(
            "channel_id",
            sa.Integer(),
            sa.ForeignKey("channels.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.CheckConstraint(
            "(conversation_id IS NOT NULL AND channel_id IS NULL) OR "
            "(conversation_id IS NULL AND channel_id IS NOT NULL)",
            name="check_chat_folder_item_target",
        ),
    )
    op.create_index("ix_chat_folder_items_folder_id", "chat_folder_items", ["folder_id"])
    op.create_index(
        "ix_chat_folder_items_conversation_id", "chat_folder_items", ["conversation_id"]
    )
    op.create_index("ix_chat_folder_items_channel_id", "chat_folder_items", ["channel_id"])
    op.create_unique_constraint(
        "uq_chat_folder_conversation",
        "chat_folder_items",
        ["folder_id", "conversation_id"],
    )
    op.create_unique_constraint(
        "uq_chat_folder_channel",
        "chat_folder_items",
        ["folder_id", "channel_id"],
    )


def downgrade() -> None:
    op.drop_table("chat_folder_items")
    op.drop_table("chat_folders")
