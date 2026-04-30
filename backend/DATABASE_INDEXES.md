# Рекомендации по индексам для PostgreSQL (100k пользователей)

## Критические индексы для производительности

### 1. Таблица `posts`
```sql
-- Индекс для фильтрации по статусу и удалению (используется в feed_service)
CREATE INDEX IF NOT EXISTS idx_posts_status_deleted ON posts(status, deleted_at) WHERE deleted_at IS NULL;

-- Индекс для сортировки по дате публикации
CREATE INDEX IF NOT EXISTS idx_posts_published_at ON posts(published_at DESC) WHERE status = 'published' AND deleted_at IS NULL;

-- Индекс для поиска по типу поста
CREATE INDEX IF NOT EXISTS idx_posts_type_status ON posts(type, status) WHERE deleted_at IS NULL;

-- Индекс для полнотекстового поиска (GIN индекс для tsvector)
CREATE INDEX IF NOT EXISTS idx_posts_search_vector ON posts USING gin(to_tsvector('russian', 
    COALESCE(title, '') || ' ' || 
    COALESCE(description, '') || ' ' || 
    COALESCE(array_to_string(tags, ' '), '')
));

-- Композитный индекс для feed запросов
CREATE INDEX IF NOT EXISTS idx_posts_user_status_published ON posts(user_id, status, published_at DESC) WHERE deleted_at IS NULL;

-- Индекс для каналов
CREATE INDEX IF NOT EXISTS idx_posts_channel_status ON posts(channel_id, status) WHERE channel_id IS NOT NULL AND deleted_at IS NULL;
```

### 2. Таблица `likes`
```sql
-- Индекс для подсчета лайков поста
CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes(post_id);

-- Индекс для проверки лайка пользователя
CREATE INDEX IF NOT EXISTS idx_likes_user_post ON likes(user_id, post_id);
```

### 3. Таблица `comments`
```sql
-- Индекс для получения комментариев поста
CREATE INDEX IF NOT EXISTS idx_comments_post_deleted ON comments(post_id, deleted_at) WHERE deleted_at IS NULL;

-- Индекс для корневых комментариев
CREATE INDEX IF NOT EXISTS idx_comments_post_parent ON comments(post_id, parent_id) WHERE parent_id IS NULL AND deleted_at IS NULL;

-- Индекс для сортировки по дате
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at DESC) WHERE deleted_at IS NULL;
```

### 4. Таблица `reposts`
```sql
-- Индекс для подсчета репостов
CREATE INDEX IF NOT EXISTS idx_reposts_post_id ON reposts(post_id);

-- Индекс для проверки репоста пользователя
CREATE INDEX IF NOT EXISTS idx_reposts_user_post ON reposts(user_id, post_id);

-- Индекс для получения последних репостов
CREATE INDEX IF NOT EXISTS idx_reposts_post_created ON reposts(post_id, created_at DESC);
```

### 5. Таблица `followers`
```sql
-- Индекс для получения подписчиков
CREATE INDEX IF NOT EXISTS idx_followers_followee ON followers(followee_id);

-- Индекс для получения подписок
CREATE INDEX IF NOT EXISTS idx_followers_follower ON followers(follower_id);

-- Композитный индекс для проверки подписки
CREATE INDEX IF NOT EXISTS idx_followers_follower_followee ON followers(follower_id, followee_id);
```

### 6. Таблица `users`
```sql
-- Индекс для поиска по username (уже должен быть уникальным)
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE deleted_at IS NULL;

-- Индекс для поиска по email (уже должен быть уникальным)
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE deleted_at IS NULL;
```

### 7. Таблица `channels`
```sql
-- Индекс для поиска по slug (уже должен быть уникальным)
CREATE INDEX IF NOT EXISTS idx_channels_slug ON channels(slug) WHERE deleted_at IS NULL;

-- Индекс для фильтрации по публичности
CREATE INDEX IF NOT EXISTS idx_channels_public ON channels(is_public) WHERE is_public = true AND deleted_at IS NULL;

-- Индекс для сортировки по популярности
CREATE INDEX IF NOT EXISTS idx_channels_members_count ON channels(members_count DESC) WHERE deleted_at IS NULL;
```

### 8. Таблица `channel_members`
```sql
-- Индекс для получения участников канала
CREATE INDEX IF NOT EXISTS idx_channel_members_channel ON channel_members(channel_id);

-- Индекс для получения каналов пользователя
CREATE INDEX IF NOT EXISTS idx_channel_members_user ON channel_members(user_id);

-- Композитный индекс для проверки членства
CREATE INDEX IF NOT EXISTS idx_channel_members_channel_user ON channel_members(channel_id, user_id);
```

## Как применить индексы

### Вариант 1: Через миграцию Alembic
```bash
cd backend
alembic revision -m "add_performance_indexes"
```

Затем в файле миграции добавьте все индексы выше.

### Вариант 2: Напрямую через psql
```bash
psql -U postgres -d haneat -f indexes.sql
```

### Вариант 3: Через Python скрипт
```python
from app.core.database import engine
from sqlalchemy import text

indexes = [
    "CREATE INDEX IF NOT EXISTS idx_posts_status_deleted ON posts(status, deleted_at) WHERE deleted_at IS NULL;",
    # ... остальные индексы
]

with engine.connect() as conn:
    for index_sql in indexes:
        conn.execute(text(index_sql))
    conn.commit()
```

## Мониторинг производительности

После применения индексов проверьте:

1. **Использование индексов:**
```sql
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

2. **Медленные запросы:**
```sql
SELECT query, calls, total_time, mean_time, max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
```

3. **Размер индексов:**
```sql
SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Важные замечания

1. **Partial indexes** (WHERE deleted_at IS NULL) экономят место и ускоряют запросы
2. **GIN индексы** для полнотекстового поиска могут быть большими, но критичны для производительности
3. **Композитные индексы** должны соответствовать порядку фильтров в запросах
4. Регулярно выполняйте `VACUUM ANALYZE` для обновления статистики

