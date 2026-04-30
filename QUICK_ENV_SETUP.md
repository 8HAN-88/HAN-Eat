# ⚡ Быстрая настройка .env файлов

## 📋 Что нужно создать

### 1. Backend .env файл

Создайте файл: `backend/.env`

**Минимум для запуска:**

```env
# ОБЯЗАТЕЛЬНО - сгенерируйте ключ: openssl rand -hex 32
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа

# ОБЯЗАТЕЛЬНО - ваша база данных PostgreSQL
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat

# ОБЯЗАТЕЛЬНО - Redis для кэширования
REDIS_URL=redis://localhost:6379/0
```

**Полный пример (с опциональными настройками):**

```env
# ============================================
# ОБЯЗАТЕЛЬНЫЕ
# ============================================
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа_здесь
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0

# ============================================
# НАСТРОЙКИ
# ============================================
APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000

# ============================================
# STRIPE (для подписок) - опционально
# ============================================
STRIPE_ENABLED=false
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_ID_MONTHLY=
STRIPE_PRICE_ID_YEARLY=
FRONTEND_URL=http://localhost:8080

# ============================================
# FIREBASE (для push уведомлений) - опционально
# ============================================
FIREBASE_ENABLED=false
FIREBASE_CREDENTIALS_PATH=
FIREBASE_PROJECT_ID=

# ============================================
# S3 (для медиа) - опционально
# ============================================
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ENDPOINT_URL=https://s3.amazonaws.com
S3_ACCESS_KEY=
S3_SECRET_KEY=
CDN_URL=https://cdn.haneat.com

# ============================================
# OPENAI (для модерации) - опционально
# ============================================
OPENAI_API_KEY=

# ============================================
# ОЧЕРЕДИ - опционально
# ============================================
RABBITMQ_URL=amqp://localhost:5672
REDIS_STREAMS_ENABLED=false
```

### 2. Frontend .env файл

Создайте файл: `.env` в корне проекта (`D:\HAN Eat 1\.env`)

```env
# Spoonacular API Key (опционально, для поиска рецептов)
# Получить на: https://spoonacular.com/food-api/console
SPOONACULAR_API_KEY=ваш_api_ключ_здесь
```

---

## 🔑 Как получить SECRET_KEY

**Windows (PowerShell):**
```powershell
# Установите OpenSSL или используйте Python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Или онлайн:**
- Используйте любой генератор случайных строк
- Минимум 32 символа

---

## ✅ Проверка

После создания файлов:

1. **Backend:**
   ```bash
   cd backend
   python -c "from app.core.config import settings; print('OK' if settings.SECRET_KEY else 'ERROR')"
   ```

2. **Frontend:**
   ```bash
   flutter pub get
   flutter run
   ```

---

## 📚 Подробная инструкция

См. `ENV_SETUP_GUIDE.md` для полного руководства со всеми опциями.

