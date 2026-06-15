"""Message poll votes for chat polls

Revision ID: 056_message_poll_votes_v1
Revises: 055_channel_member_inbox_prefs
"""
from alembic import op
import sqlalchemy as sa

revision = "056_message_poll_votes_v1"
down_revision = "055_channel_member_inbox_prefs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "message_poll_votes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("option_index", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["message_id"], ["messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "message_id",
            "user_id",
            "option_index",
            name="uq_message_poll_vote_user_option",
        ),
    )
    op.create_index(
        "ix_message_poll_votes_message_id",
        "message_poll_votes",
        ["message_id"],
        unique=False,
    )
    op.create_index(
        "ix_message_poll_votes_user_id",
        "message_poll_votes",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_message_poll_votes_user_id", table_name="message_poll_votes")
    op.drop_index("ix_message_poll_votes_message_id", table_name="message_poll_votes")
    op.drop_table("message_poll_votes")
