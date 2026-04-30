# Настройка Backend

## 1. Установка зависимостей

```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## 2. Настройка переменных окружения

Создайте файл `.env` в папке `backend/`:

```env
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/haneat

# Redis
REDIS_URL=redis://localhost:6379/0

# JWT
SECRET_KEY=your-secret-key-here-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# S3/Object Storage (можно использовать локальное хранилище для разработки)
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ENDPOINT_URL=https://s3.amazonaws.com
S3_ACCESS_KEY=your-access-key
S3_SECRET_KEY=your-secret-key

# CDN
CDN_URL=http://localhost:5000/uploads

# OpenAI (опционально, для модерации)
OPENAI_API_KEY=

# App
APP_NAME=H.A.N. Eat API
APP_ENV=development
DEBUG=true

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
```

## 3. Настройка базы данных

### PostgreSQL

```bash
# Создать базу данных
createdb haneat

# Или через psql:
psql -U postgres
CREATE DATABASE haneat;
```

### Применить миграции

```bash
# Инициализировать Alembic (если еще не инициализирован)
alembic init migrations

# Создать первую миграцию
alembic revision --autogenerate -m "Initial schema"

# Применить миграции
alembic upgrade head
```

## 4. Настройка Redis

```bash
# Установить Redis (если еще не установлен)
# Windows: скачать с https://github.com/microsoftarchive/redis/releases
# Linux/Mac: sudo apt-get install redis-server / brew install redis

# Запустить Redis
redis-server
```

## 5. Запуск сервера

```bash
# Development режим
uvicorn app.main:app --reload --host 0.0.0.0 --port 5000

# Или через Python
python -m uvicorn app.main:app --reload
```

Сервер будет доступен по адресу: http://localhost:5000

API документация: http://localhost:5000/docs

## 6. Тестирование

```bash
# Запустить тесты
pytest tests/

# С покрытием
pytest --cov=app tests/
```

## Troubleshooting

### Ошибка подключения к БД
- Проверьте, что PostgreSQL запущен
- Проверьте DATABASE_URL в .env
- Убедитесь, что база данных создана

### Ошибка подключения к Redis
- Проверьте, что Redis запущен
- Проверьте REDIS_URL в .env

### Ошибки импорта
- Убедитесь, что виртуальное окружение активировано
- Проверьте, что все зависимости установлены: `pip install -r requirements.txt`

