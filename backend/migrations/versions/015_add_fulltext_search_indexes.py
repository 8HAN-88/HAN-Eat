"""add fulltext search indexes

Revision ID: 015_add_fulltext_search_indexes
Revises: 014_add_image_processing
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '015_add_fulltext_search_indexes'
down_revision = '014_add_image_processing'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Создаем GIN индексы для полнотекстового поиска
    
    # Индекс для поиска в title и description
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_posts_title_description_fts 
        ON posts 
        USING GIN (to_tsvector('russian', coalesce(title, '') || ' ' || coalesce(description, '')))
    """)
    
    # Индекс для поиска в tags (используем безопасный способ)
    # Создаем функцию-обертку для array_to_string, которая будет IMMUTABLE
    op.execute("""
        CREATE OR REPLACE FUNCTION array_to_string_immutable(text[])
        RETURNS text
        LANGUAGE sql
        IMMUTABLE
        AS $$
            SELECT COALESCE(array_to_string($1, ' '), '')
        $$;
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_posts_tags_fts 
        ON posts 
        USING GIN (to_tsvector('russian', array_to_string_immutable(tags)))
    """)
    
    # Комбинированный индекс для всех текстовых полей
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_posts_fulltext_fts 
        ON posts 
        USING GIN (
            to_tsvector('russian', 
                coalesce(title, '') || ' ' || 
                coalesce(description, '') || ' ' || 
                array_to_string_immutable(tags)
            )
        )
    """)
    
    # Индекс для быстрого поиска по статусу и видимости
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_posts_status_visibility 
        ON posts (status, visibility) 
        WHERE deleted_at IS NULL
    """)


def downgrade() -> None:
    # Удаляем индексы
    op.execute("DROP INDEX IF EXISTS idx_posts_fulltext_fts")
    op.execute("DROP INDEX IF EXISTS idx_posts_tags_fts")
    op.execute("DROP INDEX IF EXISTS idx_posts_title_description_fts")
    op.execute("DROP INDEX IF EXISTS idx_posts_status_visibility")

