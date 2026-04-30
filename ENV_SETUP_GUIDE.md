# 📋 Полное руководство по настройке .env файлов

## Обзор

В проекте используются **два** `.env` файла:
1. **Backend** `.env` - в папке `backend/.env`
2. **Frontend** `.env` - в корне проекта `D:\HAN Eat 1\.env`

---

## 1. Backend .env файл

Создайте файл `backend/.env` со следующим содержимым:

### 🔴 ОБЯЗАТЕЛЬНЫЕ (без них приложение не запустится)

```env
# ============================================
# ОБЯЗАТЕЛЬНЫЕ ПЕРЕМЕННЫЕ
# ============================================

# JWT Secret Key (ОБЯЗАТЕЛЬНО!)
# Сгенерируйте случайную строку, например через: openssl rand -hex 32
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа_здесь

# База данных PostgreSQL (ОБЯЗАТЕЛЬНО!)
# Формат: postgresql://user:password@host:port/database
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat

# Redis (ОБЯЗАТЕЛЬНО для кэширования и очередей)
REDIS_URL=redis://localhost:6379/0
```

### 🟡 ВАЖНЫЕ (для полной функциональности)

```env
# ============================================
# НАСТРОЙКИ ПРИЛОЖЕНИЯ
# ============================================

# Режим работы (development | production)
APP_ENV=development
DEBUG=true

# CORS - разрешенные источники (через запятую)
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000

# ============================================
# STRIPE (для подписок) - опционально
# ============================================

# Включить Stripe (true/false)
STRIPE_ENABLED=false

# Stripe Secret Key (получить на https://dashboard.stripe.com/apikeys)
STRIPE_SECRET_KEY=sk_test_...

# Stripe Publishable Key (для frontend)
STRIPE_PUBLISHABLE_KEY=pk_test_...

# Stripe Webhook Secret (получить при настройке webhook)
STRIPE_WEBHOOK_SECRET=whsec_...

# Stripe Price IDs (создать продукты в Stripe Dashboard)
STRIPE_PRICE_ID_MONTHLY=price_...
STRIPE_PRICE_ID_YEARLY=price_...

# URL фронтенда для редиректа после оплаты
FRONTEND_URL=http://localhost:8080

# ============================================
# FIREBASE (для push уведомлений) - опционально
# ============================================

# Включить Firebase
FIREBASE_ENABLED=false

# Путь к JSON файлу с credentials Firebase
# Или используйте переменную FIREBASE_CREDENTIALS_JSON (см. ниже)
FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json

# Или JSON строка с credentials (альтернатива файлу)
# FIREBASE_CREDENTIALS_JSON={"type":"service_account","project_id":"..."}

# Project ID Firebase
FIREBASE_PROJECT_ID=your-project-id

# ============================================
# S3/Object Storage (для медиа) - опционально
# ============================================

# S3 Bucket для хранения медиа
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ENDPOINT_URL=https://s3.amazonaws.com
S3_ACCESS_KEY=your-access-key
S3_SECRET_KEY=your-secret-key

# CDN URL (если используется)
CDN_URL=https://cdn.haneat.com

# ============================================
# OPENAI (для модерации контента) - опционально
# ============================================

# OpenAI API Key для модерации
OPENAI_API_KEY=sk-...

# ============================================
# ОЧЕРЕДИ (опционально)
# ============================================

# RabbitMQ URL (если используется)
RABBITMQ_URL=amqp://localhost:5672

# Redis Streams (включить/выключить)
REDIS_STREAMS_ENABLED=false
```

### 🟢 ОПЦИОНАЛЬНЫЕ (можно оставить по умолчанию)

```env
# ============================================
# НАСТРОЙКИ ПО УМОЛЧАНИЮ (можно не менять)
# ============================================

# JWT настройки
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# Rate Limiting
RATE_LIMIT_PER_MINUTE=60

# Размеры медиа
MAX_IMAGE_SIZE_MB=10
MAX_VIDEO_SIZE_MB=100

# FFmpeg путь (если не в PATH)
# FFMPEG_PATH=/usr/bin/ffmpeg
```

---

## 2. Frontend .env файл

Создайте файл `.env` в корне проекта (`D:\HAN Eat 1\.env`):

```env
# ============================================
# FRONTEND .ENV ФАЙЛ
# ============================================

# Spoonacular API Key (для поиска рецептов)
# Получить на: https://spoonacular.com/food-api/console
SPOONACULAR_API_KEY=ваш_api_ключ_здесь

# URL Backend API (если отличается от дефолтного)
# По умолчанию определяется автоматически
# API_BASE_URL=http://localhost:8000
```

---

## 📝 Минимальная конфигурация для запуска

### Backend (backend/.env)

**Минимум для запуска:**

```env
# ОБЯЗАТЕЛЬНО
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа_здесь
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0

# Опционально (можно оставить пустым)
STRIPE_ENABLED=false
FIREBASE_ENABLED=false
OPENAI_API_KEY=
S3_ACCESS_KEY=
S3_SECRET_KEY=
```

### Frontend (.env в корне)

**Минимум для запуска:**

```env
# Опционально (приложение запустится и без этого)
SPOONACULAR_API_KEY=ваш_ключ_здесь
```

---

## 🔧 Как получить необходимые ключи

### 1. SECRET_KEY (Backend)

**Способ 1: Генерация через OpenSSL**
```bash
openssl rand -hex 32
```

**Способ 2: Генерация через Python**
```python
import secrets
print(secrets.token_urlsafe(32))
```

**Способ 3: Онлайн генератор**
- Используйте любой генератор случайных строк
- Минимум 32 символа

### 2. DATABASE_URL

Формат: `postgresql://username:password@host:port/database`

**Примеры:**
- Локально: `postgresql://postgres:mypassword@localhost:5432/haneat`
- Docker: `postgresql://postgres:postgres@db:5432/haneat`
- Cloud: `postgresql://user:pass@db.example.com:5432/haneat`

### 3. SPOONACULAR_API_KEY (Frontend)

1. Зайдите на https://spoonacular.com/food-api/console
2. Зарегистрируйтесь или войдите
3. Создайте новый API ключ
4. Скопируйте ключ в `.env`

### 4. Stripe ключи (если нужны подписки)

1. Зайдите на https://dashboard.stripe.com
2. Перейдите в **Developers** → **API keys**
3. Скопируйте:
   - **Secret key** → `STRIPE_SECRET_KEY`
   - **Publishable key** → `STRIPE_PUBLISHABLE_KEY`
4. Создайте продукты и получите Price IDs
5. Настройте webhook и получите Webhook Secret

**Подробнее:** см. `STRIPE_SETUP.md`

### 5. Firebase (если нужны push уведомления)

1. Создайте проект в https://console.firebase.google.com
2. Скачайте service account JSON
3. Укажите путь в `FIREBASE_CREDENTIALS_PATH` или используйте `FIREBASE_CREDENTIALS_JSON`

---

## ✅ Проверка конфигурации

### Backend

После создания `backend/.env`, проверьте:

```bash
cd backend
python -c "from app.core.config import settings; print('Config loaded:', settings.SECRET_KEY[:10] + '...')"
```

Если ошибок нет - конфигурация загружена правильно.

### Frontend

После создания `.env` в корне, проверьте:

```bash
flutter pub get
flutter run
```

Приложение должно запуститься (даже если некоторые функции не работают без дополнительных ключей).

---

## 🚨 Частые ошибки

### 1. "SECRET_KEY is required"

**Решение:** Добавьте `SECRET_KEY=...` в `backend/.env`

### 2. "Could not connect to database"

**Решение:** 
- Проверьте, что PostgreSQL запущен
- Проверьте правильность `DATABASE_URL`
- Проверьте права доступа пользователя

### 3. "Redis connection failed"

**Решение:**
- Проверьте, что Redis запущен
- Проверьте правильность `REDIS_URL`
- Для разработки можно использовать Docker: `docker run -d -p 6379:6379 redis`

### 4. "SPOONACULAR_API_KEY not found"

**Решение:**
- Это не критично, приложение запустится
- Для работы поиска рецептов добавьте ключ в `.env` в корне проекта

---

## 📁 Структура файлов

```
D:\HAN Eat 1\
├── .env                    # Frontend .env (SPOONACULAR_API_KEY)
├── backend/
│   └── .env               # Backend .env (все остальное)
└── ...
```

---

## 🔒 Безопасность

⚠️ **ВАЖНО:**

1. **НЕ коммитьте** `.env` файлы в Git
2. Используйте `.env.example` для шаблонов (без реальных ключей)
3. В production используйте переменные окружения системы
4. Храните секретные ключи в безопасном месте

---

## 📚 Дополнительная документация

- `STRIPE_SETUP.md` - настройка Stripe
- `FIREBASE_SETUP.md` - настройка Firebase
- `SETUP_INSTRUCTIONS.md` - общие инструкции по настройке

---

## 🎯 Быстрый старт

1. Создайте `backend/.env` с минимумом:
   ```env
   SECRET_KEY=ваш_ключ_32_символа
   DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
   REDIS_URL=redis://localhost:6379/0
   ```

2. Создайте `.env` в корне (опционально):
   ```env
   SPOONACULAR_API_KEY=ваш_ключ
   ```

3. Запустите приложение!

