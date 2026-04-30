# 📁 Объяснение .env файлов в проекте

## Структура проекта

У вас **три разных сервера/приложения**, каждому нужен свой `.env`:

```
D:\HAN Eat 1\
├── RecipeApp/          # Flask сервер (старый, для рецептов)
│   └── .env           # ✅ У вас уже есть
├── backend/           # FastAPI сервер (новый, основной)
│   └── .env           # ❌ Нужно создать
└── .env               # Flutter frontend (опционально)
```

---

## 1. RecipeApp/.env (у вас уже есть ✅)

Этот файл используется **только** Flask сервером в `RecipeApp/`.

**Что там должно быть:**
```env
SPOONACULAR_API_KEY=ваш_ключ
OPENAI_API_KEY=ваш_ключ
```

**Можно оставить как есть** - он работает для RecipeApp сервера.

---

## 2. backend/.env (нужно создать ❌)

Этот файл используется **только** FastAPI сервером в `backend/`.

**Минимум для запуска:**
```env
# ОБЯЗАТЕЛЬНЫЕ
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0

# Можно переиспользовать ключи из RecipeApp
OPENAI_API_KEY=ваш_ключ_из_RecipeApp
```

**Полный пример:**
```env
# ============================================
# ОБЯЗАТЕЛЬНЫЕ
# ============================================
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0

# ============================================
# МОЖНО СКОПИРОВАТЬ ИЗ RecipeApp/.env
# ============================================
OPENAI_API_KEY=ваш_ключ_из_RecipeApp

# ============================================
# НАСТРОЙКИ
# ============================================
APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000

# ============================================
# STRIPE (опционально)
# ============================================
STRIPE_ENABLED=false
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_ID_MONTHLY=
STRIPE_PRICE_ID_YEARLY=
FRONTEND_URL=http://localhost:8080

# ============================================
# FIREBASE (опционально)
# ============================================
FIREBASE_ENABLED=false
FIREBASE_CREDENTIALS_PATH=
FIREBASE_PROJECT_ID=

# ============================================
# S3 (опционально)
# ============================================
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ENDPOINT_URL=https://s3.amazonaws.com
S3_ACCESS_KEY=
S3_SECRET_KEY=
CDN_URL=https://cdn.haneat.com

# ============================================
# ОЧЕРЕДИ (опционально)
# ============================================
RABBITMQ_URL=amqp://localhost:5672
REDIS_STREAMS_ENABLED=false
```

---

## 3. .env в корне (опционально)

Для Flutter frontend (если нужен поиск рецептов через Spoonacular).

**Можно скопировать ключ из RecipeApp:**
```env
SPOONACULAR_API_KEY=ваш_ключ_из_RecipeApp
```

---

## 💡 Можно ли использовать один файл?

**Технически можно**, но **не рекомендуется**, потому что:

1. **Разные серверы** - RecipeApp (Flask) и backend (FastAPI) - это разные приложения
2. **Разные пути** - каждый сервер ищет `.env` в своей папке
3. **Безопасность** - лучше разделять конфигурацию

### Альтернатива: Символическая ссылка (для Windows)

Если очень хочется использовать один файл, можно создать символическую ссылку:

**Windows (PowerShell от администратора):**
```powershell
# Создать ссылку из backend/.env на RecipeApp/.env
New-Item -ItemType SymbolicLink -Path "backend\.env" -Target "RecipeApp\.env"
```

Но это **не рекомендуется**, так как:
- RecipeApp использует только `SPOONACULAR_API_KEY` и `OPENAI_API_KEY`
- Backend нужны другие переменные (`SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, и т.д.)

---

## ✅ Рекомендуемое решение

### Вариант 1: Раздельные файлы (рекомендуется)

1. **RecipeApp/.env** - оставить как есть ✅
2. **backend/.env** - создать новый, скопировать `OPENAI_API_KEY` из RecipeApp
3. **.env в корне** - создать, скопировать `SPOONACULAR_API_KEY` из RecipeApp

### Вариант 2: Общий файл с недостающими переменными

Можно добавить недостающие переменные в `RecipeApp/.env`:

```env
# Существующие (у вас уже есть)
SPOONACULAR_API_KEY=ваш_ключ
OPENAI_API_KEY=ваш_ключ

# Добавить для backend
SECRET_KEY=ваш_секретный_ключ_минимум_32_символа
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0
```

И создать символическую ссылку:
```powershell
New-Item -ItemType SymbolicLink -Path "backend\.env" -Target "RecipeApp\.env"
```

---

## 🎯 Быстрый старт

### Шаг 1: Создайте backend/.env

Скопируйте `OPENAI_API_KEY` из `RecipeApp/.env` и добавьте обязательные переменные:

```env
# Скопировать из RecipeApp/.env
OPENAI_API_KEY=ваш_ключ_из_RecipeApp

# Добавить новые (обязательные)
SECRET_KEY=сгенерируйте_ключ_32_символа
DATABASE_URL=postgresql://postgres:password@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0
```

### Шаг 2: (Опционально) Создайте .env в корне

Скопируйте `SPOONACULAR_API_KEY` из `RecipeApp/.env`:

```env
SPOONACULAR_API_KEY=ваш_ключ_из_RecipeApp
```

---

## 📝 Итого

- ✅ **RecipeApp/.env** - оставить как есть
- ❌ **backend/.env** - создать новый, скопировать `OPENAI_API_KEY`
- ⚠️ **.env в корне** - опционально, скопировать `SPOONACULAR_API_KEY`

**Главное:** Backend нужен свой `.env` с `SECRET_KEY`, `DATABASE_URL` и `REDIS_URL` - это обязательные переменные, которых нет в RecipeApp.

