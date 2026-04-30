"""
Скрипт для применения индексов производительности PostgreSQL
Использование: python apply_indexes.py
"""
import sys
from sqlalchemy import text
from app.core.database import engine
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Список индексов для создания
INDEXES = [
    # Posts indexes
    """
    CREATE INDEX IF NOT EXISTS idx_posts_status_deleted 
    ON posts(status, deleted_at) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_posts_published_at 
    ON posts(published_at DESC) 
    WHERE status = 'published' AND deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_posts_type_status 
    ON posts(type, status) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_posts_user_status_published 
    ON posts(user_id, status, published_at DESC) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_posts_channel_status 
    ON posts(channel_id, status) 
    WHERE channel_id IS NOT NULL AND deleted_at IS NULL;
    """,
    
    # Likes indexes
    """
    CREATE INDEX IF NOT EXISTS idx_likes_post_id 
    ON likes(post_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_likes_user_post 
    ON likes(user_id, post_id);
    """,
    
    # Comments indexes
    """
    CREATE INDEX IF NOT EXISTS idx_comments_post_deleted 
    ON comments(post_id, deleted_at) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_comments_post_parent 
    ON comments(post_id, parent_id) 
    WHERE parent_id IS NULL AND deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_comments_created_at 
    ON comments(created_at DESC) 
    WHERE deleted_at IS NULL;
    """,
    
    # Reposts indexes
    """
    CREATE INDEX IF NOT EXISTS idx_reposts_post_id 
    ON reposts(post_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_reposts_user_post 
    ON reposts(user_id, post_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_reposts_post_created 
    ON reposts(post_id, created_at DESC);
    """,
    
    # Followers indexes
    """
    CREATE INDEX IF NOT EXISTS idx_followers_followee 
    ON followers(followee_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_followers_follower 
    ON followers(follower_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_followers_follower_followee 
    ON followers(follower_id, followee_id);
    """,
    
    # Users indexes
    """
    CREATE INDEX IF NOT EXISTS idx_users_username 
    ON users(username) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_users_email 
    ON users(email) 
    WHERE deleted_at IS NULL;
    """,
    
    # Channels indexes
    """
    CREATE INDEX IF NOT EXISTS idx_channels_slug 
    ON channels(slug) 
    WHERE deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_channels_public 
    ON channels(is_public) 
    WHERE is_public = true AND deleted_at IS NULL;
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_channels_members_count 
    ON channels(members_count DESC) 
    WHERE deleted_at IS NULL;
    """,
    
    # Channel members indexes
    """
    CREATE INDEX IF NOT EXISTS idx_channel_members_channel 
    ON channel_members(channel_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_channel_members_user 
    ON channel_members(user_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_channel_members_channel_user 
    ON channel_members(channel_id, user_id);
    """,
]

# GIN индекс для полнотекстового поиска (требует расширение pg_trgm)
FULLTEXT_INDEX = """
CREATE INDEX IF NOT EXISTS idx_posts_search_vector 
ON posts USING gin(to_tsvector('russian', 
    COALESCE(title, '') || ' ' || 
    COALESCE(description, '') || ' ' || 
    COALESCE(array_to_string(tags, ' '), '')
));
"""


def apply_indexes():
    """Применить все индексы к базе данных"""
    logger.info("Начинаем применение индексов...")
    
    try:
        with engine.connect() as conn:
            # Применяем обычные индексы
            for i, index_sql in enumerate(INDEXES, 1):
                try:
                    logger.info(f"Применяем индекс {i}/{len(INDEXES)}...")
                    conn.execute(text(index_sql.strip()))
                    conn.commit()
                    logger.info(f"✅ Индекс {i} применен успешно")
                except Exception as e:
                    logger.warning(f"⚠️ Ошибка при применении индекса {i}: {e}")
                    conn.rollback()
            
            # Применяем GIN индекс для полнотекстового поиска
            try:
                logger.info("Применяем GIN индекс для полнотекстового поиска...")
                conn.execute(text(FULLTEXT_INDEX.strip()))
                conn.commit()
                logger.info("✅ GIN индекс применен успешно")
            except Exception as e:
                logger.warning(f"⚠️ Не удалось применить GIN индекс (возможно, требуется расширение pg_trgm): {e}")
                logger.info("Для полнотекстового поиска может потребоваться: CREATE EXTENSION IF NOT EXISTS pg_trgm;")
                conn.rollback()
        
        logger.info("✅ Все индексы применены успешно!")
        return True
        
    except Exception as e:
        logger.error(f"❌ Критическая ошибка при применении индексов: {e}", exc_info=True)
        return False


if __name__ == "__main__":
    success = apply_indexes()
    sys.exit(0 if success else 1)

