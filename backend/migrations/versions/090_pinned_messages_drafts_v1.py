"""conversation_pinned_messages + conversation_drafts

Revision ID: 090_pinned_messages_drafts_v1
Revises: 089_show_read_receipts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "090_pinned_messages_drafts_v1"
down_revision = "089_show_read_receipts_v1"
branch_labels = None
depends_on = None


def _tables() -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return set(inspector.get_table_names())


def upgrade() -> None:
    tables = _tables()
    if "conversation_pinned_messages" not in tables:
        op.create_table(
            "conversation_pinned_messages",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "conversation_id",
                sa.Integer(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                nullable=False,
                index=True,
            ),
            sa.Column(
                "message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="CASCADE"),
                nullable=False,
                index=True,
            ),
            sa.Column(
                "pinned_by_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("pinned_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint(
                "conversation_id",
                "message_id",
                name="uq_conversation_pinned_message",
            ),
        )
        # Backfill from legacy single pin slot (only live messages).
        op.execute(
            """
            INSERT INTO conversation_pinned_messages
                (conversation_id, message_id, pinned_by_user_id, pinned_at)
            SELECT
                c.id,
                c.pinned_message_id,
                c.pinned_by_user_id,
                COALESCE(c.pinned_at, CURRENT_TIMESTAMP)
            FROM conversations c
            JOIN messages m
              ON m.id = c.pinned_message_id
             AND m.deleted_at IS NULL
            WHERE c.pinned_message_id IS NOT NULL
            ON CONFLICT (conversation_id, message_id) DO NOTHING
            """
        )

    if "conversation_drafts" not in tables:
        op.create_table(
            "conversation_drafts",
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                primary_key=True,
            ),
            sa.Column(
                "conversation_id",
                sa.Integer(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                primary_key=True,
            ),
            sa.Column("text", sa.String(4000), nullable=False, server_default=""),
            sa.Column(
                "reply_to_message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(),
                nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            ),
        )


def downgrade() -> None:
    tables = _tables()
    if "conversation_drafts" in tables:
        op.drop_table("conversation_drafts")
    if "conversation_pinned_messages" in tables:
        op.drop_table("conversation_pinned_messages")
