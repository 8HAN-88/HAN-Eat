"""Idempotent chat sends via client_message_id

Revision ID: 059_message_client_id_v1
Revises: 058_user_phone_e164_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "059_message_client_id_v1"
down_revision = "058_user_phone_e164_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "messages",
        sa.Column("client_message_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "uq_messages_client_message_id",
        "messages",
        ["conversation_id", "sender_id", "client_message_id"],
        unique=True,
        postgresql_where=sa.text("client_message_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_messages_client_message_id", table_name="messages")
    op.drop_column("messages", "client_message_id")
