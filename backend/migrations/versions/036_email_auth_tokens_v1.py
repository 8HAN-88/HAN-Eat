"""Email verification and auth tokens

Revision ID: 036_email_auth_tokens_v1
Revises: 035_channel_member_status_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "036_email_auth_tokens_v1"
down_revision = "035_channel_member_status_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email_verified_at", sa.DateTime(), nullable=True),
    )
    op.execute("UPDATE users SET email_verified_at = created_at WHERE email_verified_at IS NULL")

    op.create_table(
        "auth_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("extra_data", sa.Text(), nullable=True),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_auth_tokens_token_hash", "auth_tokens", ["token_hash"], unique=True)
    op.create_index("ix_auth_tokens_user_purpose", "auth_tokens", ["user_id", "purpose"])


def downgrade() -> None:
    op.drop_index("ix_auth_tokens_user_purpose", table_name="auth_tokens")
    op.drop_index("ix_auth_tokens_token_hash", table_name="auth_tokens")
    op.drop_table("auth_tokens")
    op.drop_column("users", "email_verified_at")
