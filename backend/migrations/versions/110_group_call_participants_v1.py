"""Group call participants + nullable callee for group calls

Revision ID: 110_group_call_participants_v1
Revises: 109_user_voip_token_v1
Create Date: 2026-08-02
"""

from alembic import op
import sqlalchemy as sa


revision = "110_group_call_participants_v1"
down_revision = "109_user_voip_token_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "call_sessions",
        sa.Column("kind", sa.String(length=16), nullable=False, server_default="direct"),
    )
    op.alter_column("call_sessions", "callee_id", existing_type=sa.Integer(), nullable=True)
    op.create_table(
        "call_participants",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "call_id",
            sa.Integer(),
            sa.ForeignKey("call_sessions.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        # invited | ringing | joined | left | rejected | missed
        sa.Column("status", sa.String(length=24), nullable=False, server_default="invited"),
        sa.Column("joined_at", sa.DateTime(), nullable=True),
        sa.Column("left_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.UniqueConstraint("call_id", "user_id", name="uq_call_participants_call_user"),
    )
    op.create_index("ix_call_participants_call_status", "call_participants", ["call_id", "status"])


def downgrade() -> None:
    op.drop_index("ix_call_participants_call_status", table_name="call_participants")
    op.drop_table("call_participants")
    op.alter_column("call_sessions", "callee_id", existing_type=sa.Integer(), nullable=False)
    op.drop_column("call_sessions", "kind")
