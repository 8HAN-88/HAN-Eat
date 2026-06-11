"""Chat v2: per-chat mute and user blocks

Revision ID: 050_chat_v2_mute_blocks
Revises: 049_phone_contacts_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "050_chat_v2_mute_blocks"
down_revision = "049_phone_contacts_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "conversation_members",
        sa.Column("muted_at", sa.DateTime(), nullable=True),
    )
    op.create_table(
        "user_blocks",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("blocker_user_id", sa.Integer(), nullable=False),
        sa.Column("blocked_user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["blocker_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocked_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "blocker_user_id",
            "blocked_user_id",
            name="uq_user_block_pair",
        ),
    )
    op.create_index("ix_user_blocks_blocker_user_id", "user_blocks", ["blocker_user_id"])
    op.create_index("ix_user_blocks_blocked_user_id", "user_blocks", ["blocked_user_id"])


def downgrade() -> None:
    op.drop_index("ix_user_blocks_blocked_user_id", table_name="user_blocks")
    op.drop_index("ix_user_blocks_blocker_user_id", table_name="user_blocks")
    op.drop_table("user_blocks")
    op.drop_column("conversation_members", "muted_at")
