"""conversation_members.muted_until for timed mute sync

Revision ID: 092_muted_until_v1
Revises: 091_auto_delete_seconds_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "092_muted_until_v1"
down_revision = "091_auto_delete_seconds_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("conversation_members")
    if "muted_until" not in cols:
        op.add_column(
            "conversation_members",
            sa.Column("muted_until", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    cols = _columns("conversation_members")
    if "muted_until" in cols:
        op.drop_column("conversation_members", "muted_until")
