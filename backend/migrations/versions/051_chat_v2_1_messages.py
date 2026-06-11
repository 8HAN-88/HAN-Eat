"""Chat v2.1: message edit, reactions, pinned message

Revision ID: 051_chat_v2_1_messages
Revises: 050_chat_v2_mute_blocks
"""
from alembic import op
import sqlalchemy as sa

revision = "051_chat_v2_1_messages"
down_revision = "050_chat_v2_mute_blocks"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "messages",
        sa.Column("edited_at", sa.DateTime(), nullable=True),
    )
    op.create_table(
        "message_reactions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("emoji", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["message_id"], ["messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("message_id", "user_id", name="uq_message_reaction_user"),
    )
    op.create_index(
        "ix_message_reactions_message_id", "message_reactions", ["message_id"]
    )
    op.add_column(
        "conversations",
        sa.Column("pinned_message_id", sa.Integer(), nullable=True),
    )
    op.add_column(
        "conversations",
        sa.Column("pinned_at", sa.DateTime(), nullable=True),
    )
    op.add_column(
        "conversations",
        sa.Column("pinned_by_user_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_conversations_pinned_message_id",
        "conversations",
        "messages",
        ["pinned_message_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_conversations_pinned_by_user_id",
        "conversations",
        "users",
        ["pinned_by_user_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_conversations_pinned_by_user_id", "conversations", type_="foreignkey"
    )
    op.drop_constraint(
        "fk_conversations_pinned_message_id", "conversations", type_="foreignkey"
    )
    op.drop_column("conversations", "pinned_by_user_id")
    op.drop_column("conversations", "pinned_at")
    op.drop_column("conversations", "pinned_message_id")
    op.drop_index("ix_message_reactions_message_id", table_name="message_reactions")
    op.drop_table("message_reactions")
    op.drop_column("messages", "edited_at")
