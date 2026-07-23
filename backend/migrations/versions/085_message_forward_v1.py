"""message forward attribution fields

Revision ID: 085_message_forward_v1
Revises: 084_message_hides_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "085_message_forward_v1"
down_revision = "084_message_hides_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    cols = _columns("messages")
    if "forward_from_user_id" not in cols:
        op.add_column(
            "messages",
            sa.Column(
                "forward_from_user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )
    if "forward_from_name" not in cols:
        op.add_column(
            "messages",
            sa.Column("forward_from_name", sa.String(120), nullable=True),
        )
    if "forwarded_from_message_id" not in cols:
        op.add_column(
            "messages",
            sa.Column(
                "forwarded_from_message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )


def downgrade() -> None:
    cols = _columns("messages")
    if "forwarded_from_message_id" in cols:
        op.drop_column("messages", "forwarded_from_message_id")
    if "forward_from_name" in cols:
        op.drop_column("messages", "forward_from_name")
    if "forward_from_user_id" in cols:
        op.drop_column("messages", "forward_from_user_id")
