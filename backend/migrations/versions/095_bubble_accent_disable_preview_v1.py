"""conversation_members.bubble_accent + messages.disable_webpage_preview

Revision ID: 095_bubble_accent_disable_preview_v1
Revises: 094_reactions_seen_at_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "095_bubble_accent_disable_preview_v1"
down_revision = "094_reactions_seen_at_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    member_cols = _columns("conversation_members")
    if "bubble_accent" not in member_cols:
        op.add_column(
            "conversation_members",
            sa.Column("bubble_accent", sa.String(length=32), nullable=True),
        )
    msg_cols = _columns("messages")
    if "disable_webpage_preview" not in msg_cols:
        op.add_column(
            "messages",
            sa.Column(
                "disable_webpage_preview",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            ),
        )


def downgrade() -> None:
    msg_cols = _columns("messages")
    if "disable_webpage_preview" in msg_cols:
        op.drop_column("messages", "disable_webpage_preview")
    member_cols = _columns("conversation_members")
    if "bubble_accent" in member_cols:
        op.drop_column("conversation_members", "bubble_accent")
