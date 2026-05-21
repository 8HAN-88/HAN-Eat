"""Meal plan generation cooldown for free tier

Revision ID: 033_meal_plan_cooldown_v1
Revises: 032_ai_meal_plans_v1
"""
from alembic import op
import sqlalchemy as sa

revision = "033_meal_plan_cooldown_v1"
down_revision = "032_ai_meal_plans_v1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("meal_plan_last_generated_at", sa.DateTime(), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("meal_plan_cooldown_ends_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "meal_plan_cooldown_ends_at")
    op.drop_column("users", "meal_plan_last_generated_at")
