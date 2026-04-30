"""Add base recipes table for Russian recipes

Revision ID: 023_base_recipes
Revises: 022_spoonacular_saved
Create Date: 2025-01-XX XX:XX:XX.XXXXXX
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = '023_base_recipes'
down_revision = '022_spoonacular_saved'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'base_recipes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=500), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('ingredients', postgresql.JSONB(), nullable=False),
        sa.Column('steps', postgresql.JSONB(), nullable=False),
        sa.Column('image_url', sa.String(), nullable=True),
        sa.Column('calories', sa.Integer(), nullable=True),
        sa.Column('nutrition', postgresql.JSONB(), nullable=True),
        sa.Column('tags', postgresql.JSONB(), nullable=True),
        sa.Column('search_keywords', postgresql.JSONB(), nullable=True),
        sa.Column('source', sa.String(length=100), nullable=True),
        sa.Column('popularity_score', sa.Integer(), server_default='0', nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('idx_base_recipes_title', 'base_recipes', ['title'])


def downgrade() -> None:
    op.drop_index('idx_base_recipes_title', table_name='base_recipes')
    op.drop_table('base_recipes')




