"""Post poll votes

Revision ID: 037_post_poll_votes_v1
Revises: 036_email_auth_tokens_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "037_post_poll_votes_v1"
down_revision = "036_email_auth_tokens_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "post_poll_votes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("post_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("option_index", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["post_id"], ["posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("post_id", "user_id", name="_post_poll_user_vote_uc"),
    )
    op.create_index("ix_post_poll_votes_post_id", "post_poll_votes", ["post_id"])
    op.create_index("ix_post_poll_votes_user_id", "post_poll_votes", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_post_poll_votes_user_id", table_name="post_poll_votes")
    op.drop_index("ix_post_poll_votes_post_id", table_name="post_poll_votes")
    op.drop_table("post_poll_votes")
