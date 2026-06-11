"""Chat folder auto-filters (Telegram-style)

Revision ID: 054_chat_folder_filters
Revises: 053_chat_folders
"""
from alembic import op
import sqlalchemy as sa

revision = "054_chat_folder_filters"
down_revision = "053_chat_folders"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "chat_folders",
        sa.Column("filters_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("chat_folders", "filters_json")
