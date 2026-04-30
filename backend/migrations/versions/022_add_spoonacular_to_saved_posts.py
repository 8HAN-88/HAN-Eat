"""Add spoonacular recipe support to saved_posts

Revision ID: 022_spoonacular_saved
Revises: 021_post_views
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '022_spoonacular_saved'
down_revision = '021_post_views'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Делаем post_id nullable для поддержки рецептов Spoonacular
    op.alter_column('saved_posts', 'post_id',
                    existing_type=sa.Integer(),
                    nullable=True)
    
    # Добавляем поле для ID рецепта Spoonacular
    op.add_column('saved_posts', sa.Column('spoonacular_recipe_id', sa.Integer(), nullable=True))
    
    # Добавляем поле для данных рецепта (JSON)
    op.add_column('saved_posts', sa.Column('recipe_data', postgresql.JSON(astext_type=sa.Text()), nullable=True))
    
    # Создаем индекс для быстрого поиска по spoonacular_recipe_id
    op.create_index(op.f('ix_saved_posts_spoonacular_recipe_id'), 'saved_posts', ['spoonacular_recipe_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_saved_posts_spoonacular_recipe_id'), table_name='saved_posts')
    op.drop_column('saved_posts', 'recipe_data')
    op.drop_column('saved_posts', 'spoonacular_recipe_id')
    # Возвращаем post_id как NOT NULL (но это может вызвать проблемы, если есть NULL значения)
    op.alter_column('saved_posts', 'post_id',
                    existing_type=sa.Integer(),
                    nullable=False)

