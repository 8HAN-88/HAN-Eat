"""per-user message hides for delete-for-me

Revision ID: 084_message_hides_v1
Revises: 083_chat_delivered_receipts_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "084_message_hides_v1"
down_revision = "083_chat_delivered_receipts_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("message_hides"):
        return
    op.create_table(
        "message_hides",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "message_id",
            sa.Integer(),
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint("message_id", "user_id", name="uq_message_hide_user"),
    )


def downgrade() -> None:
    if _table_exists("message_hides"):
        op.drop_table("message_hides")
