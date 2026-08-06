"""Auth sessions for active devices list

Revision ID: 114_auth_sessions_v1
Revises: 113_story_views_reactions_v1
"""

from alembic import op
import sqlalchemy as sa


revision = "114_auth_sessions_v1"
down_revision = "113_story_views_reactions_v1"
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("auth_sessions"):
        return
    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("jti", sa.String(length=64), nullable=False),
        sa.Column("device_name", sa.String(length=120), nullable=True),
        sa.Column("device_platform", sa.String(length=40), nullable=True),
        sa.Column("user_agent", sa.String(length=512), nullable=True),
        sa.Column("ip_address", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("jti", name="uq_auth_sessions_jti"),
    )
    op.create_index("ix_auth_sessions_user_id", "auth_sessions", ["user_id"])
    op.create_index("ix_auth_sessions_jti", "auth_sessions", ["jti"])


def downgrade() -> None:
    if not _table_exists("auth_sessions"):
        return
    op.drop_index("ix_auth_sessions_jti", table_name="auth_sessions")
    op.drop_index("ix_auth_sessions_user_id", table_name="auth_sessions")
    op.drop_table("auth_sessions")
