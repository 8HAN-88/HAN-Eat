"""group member ban list

Revision ID: 074_group_member_ban_list_v1
Revises: 073_group_member_send_restrictions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "074_group_member_ban_list_v1"
down_revision = "073_group_member_send_restrictions_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("group_member_bans"):
        return
    op.create_table(
        "group_member_bans",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("conversation_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("banned_by_user_id", sa.Integer(), nullable=True),
        sa.Column("banned", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("banned_until", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=True),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=True),
        sa.ForeignKeyConstraint(["conversation_id"], ["conversations.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["banned_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("conversation_id", "user_id", name="uq_group_member_ban_pair"),
    )
    op.create_index(
        "ix_group_member_bans_conversation_id",
        "group_member_bans",
        ["conversation_id"],
        unique=False,
    )
    op.create_index(
        "ix_group_member_bans_user_id",
        "group_member_bans",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_group_member_bans_banned",
        "group_member_bans",
        ["banned"],
        unique=False,
    )
    op.create_index(
        "ix_group_member_bans_banned_until",
        "group_member_bans",
        ["banned_until"],
        unique=False,
    )


def downgrade() -> None:
    # Keep downgrade conservative to avoid destructive rollback on production data.
    pass
