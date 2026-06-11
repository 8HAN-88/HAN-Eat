"""Direct chats, messages, contacts

Revision ID: 045_chat_v1
Revises: 044_backfill_channel_post_ids
"""
from alembic import op
import sqlalchemy as sa

revision = "045_chat_v1"
down_revision = "044_backfill_channel_post_ids"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "conversations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("type", sa.String(length=20), nullable=False, server_default="direct"),
        sa.Column("direct_user_low_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("direct_user_high_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint("direct_user_low_id", "direct_user_high_id", name="uq_direct_conversation_pair"),
        sa.CheckConstraint("direct_user_low_id < direct_user_high_id", name="check_direct_pair_order"),
    )
    op.create_index("ix_conversations_type", "conversations", ["type"])
    op.create_index("ix_conversations_updated_at", "conversations", ["updated_at"])
    op.create_index("ix_conversations_direct_user_low_id", "conversations", ["direct_user_low_id"])
    op.create_index("ix_conversations_direct_user_high_id", "conversations", ["direct_user_high_id"])

    op.create_table(
        "messages",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("conversation_id", sa.Integer(), sa.ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sender_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("type", sa.String(length=20), nullable=False, server_default="text"),
        sa.Column("content", sa.String(length=4000), nullable=False, server_default=""),
        sa.Column("media_url", sa.String(length=512), nullable=True),
        sa.Column("reply_to_message_id", sa.Integer(), sa.ForeignKey("messages.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_messages_conversation_id", "messages", ["conversation_id"])
    op.create_index("ix_messages_sender_id", "messages", ["sender_id"])
    op.create_index("ix_messages_created_at", "messages", ["created_at"])

    op.create_table(
        "conversation_members",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("conversation_id", sa.Integer(), sa.ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("last_read_message_id", sa.Integer(), nullable=True),
        sa.Column("pinned", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("joined_at", sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint("conversation_id", "user_id", name="uq_conversation_member"),
    )
    op.create_index("ix_conversation_members_conversation_id", "conversation_members", ["conversation_id"])
    op.create_index("ix_conversation_members_user_id", "conversation_members", ["user_id"])

    op.create_table(
        "contacts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("contact_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint("owner_user_id", "contact_user_id", name="uq_contact_pair"),
        sa.CheckConstraint("owner_user_id != contact_user_id", name="check_no_self_contact"),
    )
    op.create_index("ix_contacts_owner_user_id", "contacts", ["owner_user_id"])
    op.create_index("ix_contacts_contact_user_id", "contacts", ["contact_user_id"])


def downgrade() -> None:
    op.drop_table("contacts")
    op.drop_table("conversation_members")
    op.drop_table("messages")
    op.drop_table("conversations")
