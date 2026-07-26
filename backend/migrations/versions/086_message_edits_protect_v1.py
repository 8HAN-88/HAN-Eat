"""message edit history + conversation protect_content

Revision ID: 086_message_edits_protect_v1
Revises: 085_message_forward_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "086_message_edits_protect_v1"
down_revision = "085_message_forward_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def _tables() -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return set(inspector.get_table_names())


def upgrade() -> None:
    cols = _columns("conversations")
    if "protect_content" not in cols:
        op.add_column(
            "conversations",
            sa.Column(
                "protect_content",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )

    if "message_edit_history" not in _tables():
        op.create_table(
            "message_edit_history",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "message_id",
                sa.Integer(),
                sa.ForeignKey("messages.id", ondelete="CASCADE"),
                nullable=False,
                index=True,
            ),
            sa.Column(
                "editor_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
                index=True,
            ),
            sa.Column("previous_content", sa.String(4000), nullable=False),
            sa.Column("edited_at", sa.DateTime(), nullable=False, index=True),
        )


def downgrade() -> None:
    if "message_edit_history" in _tables():
        op.drop_table("message_edit_history")
    cols = _columns("conversations")
    if "protect_content" in cols:
        op.drop_column("conversations", "protect_content")
