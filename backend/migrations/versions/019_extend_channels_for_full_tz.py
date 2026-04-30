"""Extend channels for full TZ requirements

Revision ID: 019_extend_channels
Revises: 018_add_category_to_channels
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '019_extend_channels'
down_revision = '018_add_category_to_channels'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Добавляем поля в channels для полного ТЗ
    op.add_column('channels', sa.Column('tags', postgresql.ARRAY(sa.String()), nullable=True))
    op.add_column('channels', sa.Column('rules', sa.Text(), nullable=True))  # Правила канала
    
    # Добавляем колонки как nullable сначала
    op.add_column('channels', sa.Column('auto_publish_to_feed', sa.Boolean(), nullable=True))
    op.add_column('channels', sa.Column('auto_publish_to_menu', sa.Boolean(), nullable=True))
    op.add_column('channels', sa.Column('allow_comments', sa.Boolean(), nullable=True))
    op.add_column('channels', sa.Column('allow_likes', sa.Boolean(), nullable=True))
    op.add_column('channels', sa.Column('allow_reposts', sa.Boolean(), nullable=True))
    
    # Устанавливаем значения по умолчанию для существующих записей
    op.execute("UPDATE channels SET auto_publish_to_feed = true WHERE auto_publish_to_feed IS NULL")
    op.execute("UPDATE channels SET auto_publish_to_menu = true WHERE auto_publish_to_menu IS NULL")
    op.execute("UPDATE channels SET allow_comments = true WHERE allow_comments IS NULL")
    op.execute("UPDATE channels SET allow_likes = true WHERE allow_likes IS NULL")
    op.execute("UPDATE channels SET allow_reposts = true WHERE allow_reposts IS NULL")
    
    # Теперь делаем их NOT NULL
    op.alter_column('channels', 'auto_publish_to_feed', nullable=False)
    op.alter_column('channels', 'auto_publish_to_menu', nullable=False)
    op.alter_column('channels', 'allow_comments', nullable=False)
    op.alter_column('channels', 'allow_likes', nullable=False)
    op.alter_column('channels', 'allow_reposts', nullable=False)
    
    # Расширяем роли в channel_members (добавляем owner)
    # owner будет определяться через admin_user_id в channels, но для совместимости добавим
    op.execute("""
        ALTER TABLE channel_members 
        DROP CONSTRAINT IF EXISTS channel_members_role_check;
    """)
    
    # Добавляем поле is_favorite в channel_members
    op.add_column('channel_members', sa.Column('is_favorite', sa.Boolean(), nullable=True, default=False))
    op.execute("UPDATE channel_members SET is_favorite = false WHERE is_favorite IS NULL")
    op.alter_column('channel_members', 'is_favorite', nullable=False)
    
    # Добавляем индекс для поиска по тегам
    op.create_index('ix_channels_tags', 'channels', ['tags'], postgresql_using='gin', unique=False)
    
    # Добавляем поле для связи рецепта с каналом (если нужно)
    # Это уже есть в posts через channel_id, но можно добавить recipe_id для прямой связи
    op.add_column('posts', sa.Column('recipe_id', sa.Integer(), nullable=True))
    op.create_index('ix_posts_recipe_id', 'posts', ['recipe_id'])


def downgrade() -> None:
    op.drop_index('ix_posts_recipe_id', 'posts')
    op.drop_column('posts', 'recipe_id')
    op.drop_index('ix_channels_tags', 'channels')
    # Безопасное удаление колонки is_favorite
    op.execute("""
        ALTER TABLE channel_members 
        DROP COLUMN IF EXISTS is_favorite;
    """)
    op.drop_column('channels', 'allow_reposts')
    op.drop_column('channels', 'allow_likes')
    op.drop_column('channels', 'allow_comments')
    op.drop_column('channels', 'auto_publish_to_menu')
    op.drop_column('channels', 'auto_publish_to_feed')
    op.drop_column('channels', 'rules')
    op.drop_column('channels', 'tags')

