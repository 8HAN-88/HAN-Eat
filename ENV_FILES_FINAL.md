# 📋 Финальные .env файлы - что должно быть

## 📁 Структура файлов

У вас должно быть **два** `.env` файла:

1. **`backend/.env`** - для FastAPI backend
2. **`.env`** в корне проекта - для Flutter frontend

---

## 1. backend/.env

Создайте файл `backend/.env` со следующим содержимым:

```env
# ============================================
# ОБЯЗАТЕЛЬНЫЕ ПЕРЕМЕННЫЕ (без них не запустится!)
# ============================================

# JWT Secret Key - сгенерируйте случайную строку минимум 32 символа
# 🔗 Онлайн генератор: https://www.lastpass.com/features/password-generator
# 🔗 Или через PowerShell: python -c "import secrets; print(secrets.token_urlsafe(32))"
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа_здесь

# PostgreSQL Database URL
# Формат: postgresql://username:password@host:port/database
# 🔗 Если используете Docker: postgresql://postgres:postgres@localhost:5432/haneat
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat

# Redis URL
# 🔗 Если используете Docker: redis://localhost:6379/0
REDIS_URL=redis://localhost:6379/0

# ============================================
# НАСТРОЙКИ ПРИЛОЖЕНИЯ
# ============================================

APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000

# ============================================
# ЮKASSA (для подписок в России) - РЕКОМЕНДУЕТСЯ
# ============================================
# 🔗 Личный кабинет: https://yookassa.ru/my
# 🔗 Регистрация: https://yookassa.ru/join
# 🔗 Документация: https://yookassa.ru/developers/api
# 
# После регистрации:
# 1. Перейдите в Настройки → API
# 2. Скопируйте Shop ID и Secret Key
# 3. Настройте webhook URL: https://your-backend-url.com/api/v1/payments/webhook/yookassa
# 
# Поддерживает: СБП, банковские карты, электронные кошельки
YOOKASSA_ENABLED=true
# 🔗 Получить Shop ID: https://yookassa.ru/my → Настройки → API
YOOKASSA_SHOP_ID=ваш_yookassa_shop_id
# 🔗 Получить Secret Key: https://yookassa.ru/my → Настройки → API
YOOKASSA_SECRET_KEY=ваш_yookassa_secret_key

# ============================================
# STRIPE (для подписок в других странах) - ОПЦИОНАЛЬНО
# ============================================
# 🔗 Dashboard: https://dashboard.stripe.com
# 🔗 Регистрация: https://dashboard.stripe.com/register
# 
# Пока отключено - можно включить позже для других стран
STRIPE_ENABLED=false
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_ID_MONTHLY=
STRIPE_PRICE_ID_YEARLY=

# URL фронтенда для редиректа после оплаты
FRONTEND_URL=http://localhost:8080

# ============================================
# OPENAI API KEY (для модерации контента)
# ============================================
# 🔗 Получить ключ: https://platform.openai.com/api-keys
# 🔗 Регистрация: https://platform.openai.com/signup
# 💡 Можно скопировать из RecipeApp/.env если там уже есть
OPENAI_API_KEY=ваш_openai_api_key

# ============================================
# FIREBASE (для push уведомлений) - ОПЦИОНАЛЬНО
# ============================================
# 🔗 Console: https://console.firebase.google.com
# 🔗 Регистрация: https://console.firebase.google.com
FIREBASE_ENABLED=false
FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json
FIREBASE_PROJECT_ID=

# ============================================
# S3/Object Storage (для хранения медиа) - ОПЦИОНАЛЬНО
# ============================================
# 🔗 AWS S3: https://aws.amazon.com/s3/
# 🔗 IAM: https://console.aws.amazon.com/iam
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ENDPOINT_URL=https://s3.amazonaws.com
S3_ACCESS_KEY=
S3_SECRET_KEY=
CDN_URL=https://cdn.haneat.com

# ============================================
# ОЧЕРЕДИ - ОПЦИОНАЛЬНО
# ============================================
RABBITMQ_URL=amqp://localhost:5672
REDIS_STREAMS_ENABLED=false
```

---

## 2. .env в корне проекта

Создайте файл `.env` в корне проекта (`D:\HAN Eat 1\.env`):

```env
# ============================================
# SPOONACULAR API KEY (для поиска рецептов)
# ============================================
# 🔗 Получить ключ: https://spoonacular.com/food-api/console
# 🔗 Регистрация: https://spoonacular.com/food-api/console
# 
# Инструкция:
# 1. Зайдите на https://spoonacular.com/food-api/console
# 2. Зарегистрируйтесь или войдите в аккаунт
# 3. Перейдите в раздел "API Keys"
# 4. Создайте новый API ключ или используйте существующий
# 5. Скопируйте ключ и вставьте ниже
# 
# 💡 Можно скопировать из RecipeApp/.env если там уже есть ключ
SPOONACULAR_API_KEY=ваш_spoonacular_api_key

# ============================================
# BACKEND API URL (опционально)
# ============================================
# По умолчанию определяется автоматически
# Раскомментируйте и измените если backend на другом адресе
# API_BASE_URL=http://localhost:8000
```

---

## ✅ Минимальная конфигурация для запуска

### backend/.env (минимум):

```env
# ОБЯЗАТЕЛЬНО
SECRET_KEY=сгенерируйте_ключ_32_символа
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0

# Для оплаты подписок (рекомендуется)
YOOKASSA_ENABLED=true
YOOKASSA_SHOP_ID=ваш_shop_id
YOOKASSA_SECRET_KEY=ваш_secret_key

# Опционально (можно оставить пустым)
OPENAI_API_KEY=
FIREBASE_ENABLED=false
STRIPE_ENABLED=false
```

### .env в корне (опционально):

```env
SPOONACULAR_API_KEY=ваш_ключ
```

---

## 🔑 Как получить ключи

### 1. SECRET_KEY

**PowerShell:**
```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Или онлайн:** https://www.lastpass.com/features/password-generator

### 2. DATABASE_URL

Если используете Docker (рекомендуется):
```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/haneat
```

Если локальная установка PostgreSQL:
```env
DATABASE_URL=postgresql://postgres:ваш_пароль@localhost:5432/haneat
```

### 3. REDIS_URL

Если используете Docker:
```env
REDIS_URL=redis://localhost:6379/0
```

### 4. YOOKASSA ключи (для оплаты)

1. Зарегистрируйтесь: https://yookassa.ru/join
2. Получите ключи: https://yookassa.ru/my → Настройки → API
3. Скопируйте Shop ID и Secret Key

### 5. OPENAI_API_KEY

- 🔗 Получить: https://platform.openai.com/api-keys
- 💡 Можно скопировать из `RecipeApp/.env` если там уже есть

### 6. SPOONACULAR_API_KEY

- 🔗 Получить: https://spoonacular.com/food-api/console
- 💡 Можно скопировать из `RecipeApp/.env` если там уже есть

---

## 📝 Быстрое создание файлов

### Вариант 1: Использовать скрипт

```cmd
create_env_files.bat
```

Или PowerShell:
```powershell
.\create_env_files.ps1
```

### Вариант 2: Вручную

```cmd
copy backend\env_template.txt backend\.env
copy env_template.txt .env
```

Затем откройте файлы и заполните значения.

---

## 🎯 Приоритеты заполнения

### 🔴 Критично (без этого не запустится):
1. `SECRET_KEY` - обязательно!
2. `DATABASE_URL` - обязательно!
3. `REDIS_URL` - обязательно!

### 🟡 Важно (для оплаты подписок):
4. `YOOKASSA_ENABLED=true`
5. `YOOKASSA_SHOP_ID` - получить на https://yookassa.ru/my
6. `YOOKASSA_SECRET_KEY` - получить на https://yookassa.ru/my

### 🟢 Опционально (можно добавить позже):
7. `OPENAI_API_KEY` - для модерации контента
8. `SPOONACULAR_API_KEY` - для поиска рецептов
9. `FIREBASE_*` - для push уведомлений
10. `S3_*` - для хранения медиа

---

## ✅ Проверка

После создания файлов проверьте:

**Backend:**
```bash
cd backend
python -c "from app.core.config import settings; print('✅ OK' if settings.SECRET_KEY else '❌ SECRET_KEY missing')"
```

**Frontend:**
```bash
flutter pub get
flutter run
```

---

## 📚 Дополнительная документация

- `ENV_SETUP_GUIDE.md` - полное руководство
- `ENV_FILES_READY.md` - инструкция по созданию файлов
- `YOOKASSA_SBP_SETUP.md` - настройка ЮKassa
- `DATABASE_REDIS_SETUP.md` - настройка PostgreSQL и Redis

---

## 💡 Важно

1. **Не коммитьте** `.env` файлы в Git
2. Все ссылки для получения ключей уже указаны в шаблонах
3. Можно скопировать ключи из `RecipeApp/.env` (OPENAI_API_KEY, SPOONACULAR_API_KEY)

