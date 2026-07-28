"""conversations.auto_delete_seconds for chat TTL

Revision ID: 091_auto_delete_seconds_v1
Revises: 090_pinned_messages_drafts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "091_auto_delete_seconds_v1"
down_revision = "090_pinned_messages_drafts_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversations")
    if "auto_delete_seconds" not in cols:
        op.add_column(
            "conversations",
            sa.Column(
                "auto_delete_seconds",
                sa.Integer(),
                nullable=False,
                server_default="0",
            ),
        )


def downgrade() -> None:
    cols = _columns("conversations")
    if "auto_delete_seconds" in cols:
        op.drop_column("conversations", "auto_delete_seconds")
