"""conversations.avatar_url + users.show_last_seen

Revision ID: 088_group_avatar_show_last_seen_v1
Revises: 087_history_cleared_before_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "088_group_avatar_show_last_seen_v1"
down_revision = "087_history_cleared_before_v1"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    conv_cols = _columns("conversations")
    if "avatar_url" not in conv_cols:
        op.add_column(
            "conversations",
            sa.Column("avatar_url", sa.Text(), nullable=True),
        )

    user_cols = _columns("users")
    if "show_last_seen" not in user_cols:
        op.add_column(
            "users",
            sa.Column(
                "show_last_seen",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("true"),
            ),
        )


def downgrade() -> None:
    conv_cols = _columns("conversations")
    if "avatar_url" in conv_cols:
        op.drop_column("conversations", "avatar_url")

    user_cols = _columns("users")
    if "show_last_seen" in user_cols:
        op.drop_column("users", "show_last_seen")
