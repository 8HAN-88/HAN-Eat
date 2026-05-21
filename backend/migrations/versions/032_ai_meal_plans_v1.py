"""AI meal plans persistence + meal_plan_entries

Revision ID: 032_ai_meal_plans_v1
Revises: 031_receipt_refund_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "032_ai_meal_plans_v1"
down_revision = "031_receipt_refund_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_meal_plans",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("plan_id", sa.String(length=64), nullable=False),
        sa.Column("duration_days", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("family_size", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("plan_data", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_meal_plans_user_id", "ai_meal_plans", ["user_id"])
    op.create_index("ix_ai_meal_plans_plan_id", "ai_meal_plans", ["plan_id"])
    op.create_index("ix_ai_meal_plans_created_at", "ai_meal_plans", ["created_at"])

    op.create_table(
        "meal_plan_entries",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("recipe_id", sa.Integer(), nullable=True),
        sa.Column("meal_date", sa.Date(), nullable=False),
        sa.Column("meal_type", sa.String(length=20), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False, server_default="manual"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_meal_plan_entries_user_date", "meal_plan_entries", ["user_id", "meal_date"])
    op.create_index("ix_meal_plan_entries_recipe_id", "meal_plan_entries", ["recipe_id"])


def downgrade() -> None:
    op.drop_table("meal_plan_entries")
    op.drop_table("ai_meal_plans")
