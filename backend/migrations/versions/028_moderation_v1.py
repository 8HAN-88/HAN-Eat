"""Moderation V1: AI scores, trust, audit, reports, feed visibility

Revision ID: 028_moderation_v1
Revises: 027_ai_scan_credits
"""
from alembic import op
import sqlalchemy as sa

revision = "028_moderation_v1"
down_revision = "027_ai_scan_credits"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("trust_score", sa.Float(), nullable=False, server_default="0.5"),
    )
    op.add_column(
        "users",
        sa.Column("account_warnings", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "users",
        sa.Column(
            "shadow_moderation",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.add_column(
        "users",
        sa.Column("banned_at", sa.DateTime(), nullable=True),
    )

    op.add_column(
        "posts",
        sa.Column(
            "hidden_from_recommendations",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )

    op.add_column(
        "moderation_queue",
        sa.Column("toxicity_score", sa.Float(), nullable=True),
    )
    op.add_column(
        "moderation_queue",
        sa.Column("spam_score", sa.Float(), nullable=True),
    )
    op.add_column(
        "moderation_queue",
        sa.Column("nsfw_score", sa.Float(), nullable=True),
    )
    op.add_column(
        "moderation_queue",
        sa.Column("danger_score", sa.Float(), nullable=True),
    )
    op.add_column(
        "moderation_queue",
        sa.Column("ai_decision", sa.String(20), nullable=True),
    )
    op.add_column(
        "moderation_queue",
        sa.Column("report_category", sa.String(50), nullable=True),
    )

    op.create_table(
        "content_reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("content_type", sa.String(20), nullable=False, index=True),
        sa.Column("content_id", sa.Integer(), nullable=False, index=True),
        sa.Column(
            "reporter_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        sa.Column("reason", sa.String(50), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), index=True),
    )
    op.create_index(
        "ix_content_reports_type_id",
        "content_reports",
        ["content_type", "content_id"],
    )

    op.create_table(
        "moderation_audit_log",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "moderator_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        sa.Column("action", sa.String(50), nullable=False, index=True),
        sa.Column("content_type", sa.String(20), nullable=True),
        sa.Column("content_id", sa.Integer(), nullable=True),
        sa.Column("target_user_id", sa.Integer(), nullable=True, index=True),
        sa.Column("details", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), index=True),
    )


def downgrade() -> None:
    op.drop_table("moderation_audit_log")
    op.drop_index("ix_content_reports_type_id", table_name="content_reports")
    op.drop_table("content_reports")
    op.drop_column("moderation_queue", "report_category")
    op.drop_column("moderation_queue", "ai_decision")
    op.drop_column("moderation_queue", "danger_score")
    op.drop_column("moderation_queue", "nsfw_score")
    op.drop_column("moderation_queue", "spam_score")
    op.drop_column("moderation_queue", "toxicity_score")
    op.drop_column("posts", "hidden_from_recommendations")
    op.drop_column("users", "banned_at")
    op.drop_column("users", "shadow_moderation")
    op.drop_column("users", "account_warnings")
    op.drop_column("users", "trust_score")
