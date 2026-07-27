"""users.show_read_receipts privacy toggle

Revision ID: 089_show_read_receipts_v1
Revises: 088_group_avatar_show_last_seen_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "089_show_read_receipts_v1"
down_revision = "088_group_avatar_show_last_seen_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("users")
    if "show_read_receipts" not in cols:
        op.add_column(
            "users",
            sa.Column(
                "show_read_receipts",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("true"),
            ),
        )


def downgrade() -> None:
    cols = _columns("users")
    if "show_read_receipts" in cols:
        op.drop_column("users", "show_read_receipts")
