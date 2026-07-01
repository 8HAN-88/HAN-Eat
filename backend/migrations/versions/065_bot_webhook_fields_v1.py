"""bot webhook fields v1

Revision ID: 065_bot_webhook_fields_v1
Revises: 064_bot_callbacks_inline_keyboards_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "065_bot_webhook_fields_v1"
down_revision = "064_bot_callbacks_inline_keyboards_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("bot_webhook_url", sa.String(length=500), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("bot_webhook_secret", sa.String(length=128), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "bot_webhook_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "users",
        sa.Column("bot_webhook_last_error", sa.Text(), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("bot_webhook_last_ok_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "bot_webhook_last_ok_at")
    op.drop_column("users", "bot_webhook_last_error")
    op.drop_column("users", "bot_webhook_enabled")
    op.drop_column("users", "bot_webhook_secret")
    op.drop_column("users", "bot_webhook_url")
