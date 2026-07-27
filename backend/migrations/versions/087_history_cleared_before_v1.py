"""conversation_members.history_cleared_before_id for clear-history

Revision ID: 087_history_cleared_before_v1
Revises: 086_message_edits_protect_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "087_history_cleared_before_v1"
down_revision = "086_message_edits_protect_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "history_cleared_before_id" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column("history_cleared_before_id", sa.Integer(), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "history_cleared_before_id" in cols:
        op.drop_column("conversation_members", "history_cleared_before_id")
