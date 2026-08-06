"""Close friends list for story privacy

Revision ID: 116_close_friends_v1
Revises: 115_user_totp_2fa_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "116_close_friends_v1"
down_revision = "115_user_totp_2fa_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("close_friends"):
        return
    op.create_table(
        "close_friends",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("friend_user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.UniqueConstraint("user_id", "friend_user_id", name="uq_close_friends_pair"),
        sa.CheckConstraint("user_id != friend_user_id", name="check_no_self_close_friend"),
    )
    op.create_index("ix_close_friends_user_id", "close_friends", ["user_id"])
    op.create_index("ix_close_friends_friend_user_id", "close_friends", ["friend_user_id"])


def downgrade() -> None:
    if not _table_exists("close_friends"):
        return
    op.drop_index("ix_close_friends_friend_user_id", table_name="close_friends")
    op.drop_index("ix_close_friends_user_id", table_name="close_friends")
    op.drop_table("close_friends")
