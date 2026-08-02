"""1:1 WebRTC call sessions

Revision ID: 108_call_sessions_v1
Revises: 107_collectible_gifts_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "108_call_sessions_v1"
down_revision = "107_collectible_gifts_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "call_sessions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "conversation_id",
            sa.Integer(),
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "caller_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "callee_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("media", sa.String(length=16), nullable=False, server_default="voice"),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="ringing"),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("ended_at", sa.DateTime(), nullable=True),
        sa.Column(
            "ended_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index("ix_call_sessions_id", "call_sessions", ["id"])
    op.create_index("ix_call_sessions_conversation_id", "call_sessions", ["conversation_id"])
    op.create_index("ix_call_sessions_caller_id", "call_sessions", ["caller_id"])
    op.create_index("ix_call_sessions_callee_id", "call_sessions", ["callee_id"])
    op.create_index("ix_call_sessions_status", "call_sessions", ["status"])
    op.create_index("ix_call_sessions_created_at", "call_sessions", ["created_at"])
    op.create_index(
        "ix_call_sessions_caller_status", "call_sessions", ["caller_id", "status"]
    )
    op.create_index(
        "ix_call_sessions_callee_status", "call_sessions", ["callee_id", "status"]
    )


def downgrade() -> None:
    op.drop_index("ix_call_sessions_callee_status", table_name="call_sessions")
    op.drop_index("ix_call_sessions_caller_status", table_name="call_sessions")
    op.drop_index("ix_call_sessions_created_at", table_name="call_sessions")
    op.drop_index("ix_call_sessions_status", table_name="call_sessions")
    op.drop_index("ix_call_sessions_callee_id", table_name="call_sessions")
    op.drop_index("ix_call_sessions_caller_id", table_name="call_sessions")
    op.drop_index("ix_call_sessions_conversation_id", table_name="call_sessions")
    op.drop_index("ix_call_sessions_id", table_name="call_sessions")
    op.drop_table("call_sessions")
