"""Rename communities to channels

Revision ID: 003_channels
Revises: 002_likes_comments
Create Date: 2025-01-XX

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '003_channels'
down_revision = '002_likes_comments'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Переименовываем таблицы
    op.rename_table('communities', 'channels')
    op.rename_table('community_members', 'channel_members')
    
    # Переименовываем индексы
    op.execute("ALTER INDEX ix_communities_id RENAME TO ix_channels_id")
    op.execute("ALTER INDEX ix_communities_slug RENAME TO ix_channels_slug")
    op.execute("ALTER INDEX ix_communities_admin_user_id RENAME TO ix_channels_admin_user_id")
    
    op.execute("ALTER INDEX ix_community_members_id RENAME TO ix_channel_members_id")
    op.execute("ALTER INDEX ix_community_members_community_id RENAME TO ix_channel_members_channel_id")
    op.execute("ALTER INDEX ix_community_members_user_id RENAME TO ix_channel_members_user_id")
    
    # Переименовываем внешние ключи (проверяем существование перед удалением)
    # Проверяем и удаляем constraint только если он существует
    op.execute("""
        DO $$ 
        BEGIN
            IF EXISTS (
                SELECT 1 FROM pg_constraint 
                WHERE conname = 'posts_community_id_fkey'
            ) THEN
                ALTER TABLE posts DROP CONSTRAINT posts_community_id_fkey;
            END IF;
        END $$;
    """)
    
    # Переименовываем колонку в posts (создаем новую и копируем данные)
    op.add_column('posts', sa.Column('channel_id', sa.Integer(), nullable=True))
    op.execute("UPDATE posts SET channel_id = community_id WHERE community_id IS NOT NULL")
    
    # Удаляем constraint еще раз на случай если он был создан после первого удаления
    op.execute("""
        DO $$ 
        BEGIN
            IF EXISTS (
                SELECT 1 FROM pg_constraint 
                WHERE conname = 'posts_community_id_fkey'
            ) THEN
                ALTER TABLE posts DROP CONSTRAINT posts_community_id_fkey;
            END IF;
        END $$;
    """)
    op.drop_column('posts', 'community_id')
    op.create_foreign_key(
        'posts_channel_id_fkey',
        'posts', 'channels',
        ['channel_id'], ['id'],
        ondelete='SET NULL'
    )
    op.create_index('ix_posts_channel_id', 'posts', ['channel_id'])
    
    # Переименовываем колонку community_id в channel_id в channel_members
    op.execute("""
        DO $$ 
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'channel_members' AND column_name = 'community_id'
            ) THEN
                ALTER TABLE channel_members RENAME COLUMN community_id TO channel_id;
            END IF;
        END $$;
    """)
    
    # Обновляем внешние ключи в channel_members (проверяем существование)
    op.execute("""
        DO $$ 
        BEGIN
            IF EXISTS (
                SELECT 1 FROM pg_constraint 
                WHERE conname = 'channel_members_community_id_fkey'
            ) THEN
                ALTER TABLE channel_members DROP CONSTRAINT channel_members_community_id_fkey;
            END IF;
        END $$;
    """)
    op.create_foreign_key(
        'channel_members_channel_id_fkey',
        'channel_members', 'channels',
        ['channel_id'], ['id'],
        ondelete='CASCADE'
    )


def downgrade() -> None:
    # Обратное переименование
    op.rename_table('channels', 'communities')
    op.rename_table('channel_members', 'community_members')
    
    # Восстанавливаем индексы
    op.execute("ALTER INDEX ix_channels_id RENAME TO ix_communities_id")
    op.execute("ALTER INDEX ix_channels_slug RENAME TO ix_communities_slug")
    op.execute("ALTER INDEX ix_channels_admin_user_id RENAME TO ix_communities_admin_user_id")
    
    op.execute("ALTER INDEX ix_channel_members_id RENAME TO ix_community_members_id")
    op.execute("ALTER INDEX ix_channel_members_channel_id RENAME TO ix_community_members_community_id")
    op.execute("ALTER INDEX ix_channel_members_user_id RENAME TO ix_community_members_user_id")
    
    # Восстанавливаем колонку community_id в posts
    op.add_column('posts', sa.Column('community_id', sa.Integer(), nullable=True))
    op.execute("UPDATE posts SET community_id = channel_id WHERE channel_id IS NOT NULL")
    op.drop_constraint('posts_channel_id_fkey', 'posts', type_='foreignkey')
    op.drop_index('ix_posts_channel_id', 'posts')
    op.drop_column('posts', 'channel_id')
    op.create_foreign_key(
        'posts_community_id_fkey',
        'posts', 'communities',
        ['community_id'], ['id'],
        ondelete='SET NULL'
    )
    
    # Восстанавливаем внешние ключи
    op.drop_constraint('channel_members_channel_id_fkey', 'community_members', type_='foreignkey')
    op.create_foreign_key(
        'community_members_community_id_fkey',
        'community_members', 'communities',
        ['community_id'], ['id'],
        ondelete='CASCADE'
    )

