-- =====================================================
-- Миграция: Поддержка ботов (BotFather) + webhook
-- Дата: 2026-06-30
-- =====================================================

-- 1. Добавляем колонки ботов в таблицу users
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_bot BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS bot_token VARCHAR(64) UNIQUE,
  ADD COLUMN IF NOT EXISTS bot_username VARCHAR(32) UNIQUE,
  ADD COLUMN IF NOT EXISTS bot_description TEXT,
  ADD COLUMN IF NOT EXISTS bot_short_description VARCHAR(120),
  ADD COLUMN IF NOT EXISTS bot_avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS created_by_user_id INTEGER REFERENCES users(id);

-- Индексы (на случай, если UNIQUE не создались автоматически)
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_bot_token ON users(bot_token) WHERE bot_token IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_bot_username ON users(bot_username) WHERE bot_username IS NOT NULL;

-- 2. Таблица команд бота
CREATE TABLE IF NOT EXISTS bot_commands (
    id SERIAL PRIMARY KEY,
    bot_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    command VARCHAR(32) NOT NULL,
    description VARCHAR(256) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(bot_id, command)
);

CREATE INDEX IF NOT EXISTS idx_bot_commands_bot_id ON bot_commands(bot_id);

-- 3. (Опционально) Таблица для хранения webhook'ов и логов (можно расширить позже)
-- ALTER TABLE users ADD COLUMN IF NOT EXISTS bot_webhook_url TEXT;
-- ALTER TABLE users ADD COLUMN IF NOT EXISTS bot_webhook_secret VARCHAR(64);

-- Готово. После выполнения миграции можно создавать ботов через BotFather в приложении.
