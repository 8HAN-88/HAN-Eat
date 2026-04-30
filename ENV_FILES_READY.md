# ✅ .env файлы готовы к использованию!

## 🚀 Быстрый старт

### Шаг 1: Создайте .env файлы из шаблонов

**Windows (PowerShell):**
```powershell
.\create_env_files.ps1
```

**Windows (CMD):**
```cmd
create_env_files.bat
```

**Или вручную:**
```cmd
copy backend\env_template.txt backend\.env
copy env_template.txt .env
```

### Шаг 2: Откройте файлы и заполните значения

Все файлы уже содержат:
- ✅ Шаблоны всех необходимых переменных
- ✅ 🔗 Прямые ссылки на страницы для получения ключей
- ✅ 📝 Подробные инструкции прямо в файлах

---

## 📁 Созданные файлы

### 1. `backend/env_template.txt` → `backend/.env`

**Обязательные переменные:**
- `SECRET_KEY` - 🔗 ссылки на генераторы
- `DATABASE_URL` - формат и примеры
- `REDIS_URL` - примеры подключения

**Опциональные:**
- `OPENAI_API_KEY` - 🔗 https://platform.openai.com/api-keys
- `STRIPE_*` - 🔗 https://dashboard.stripe.com (все ссылки внутри)
- `FIREBASE_*` - 🔗 https://console.firebase.google.com
- `S3_*` - 🔗 https://aws.amazon.com/s3/

### 2. `env_template.txt` → `.env`

**Опциональные переменные:**
- `SPOONACULAR_API_KEY` - 🔗 https://spoonacular.com/food-api/console

---

## 🔗 Все ссылки в одном месте

### Обязательные ключи

1. **SECRET_KEY** (JWT)
   - 🔗 Онлайн генератор: https://www.lastpass.com/features/password-generator
   - 🔗 PowerShell: `python -c "import secrets; print(secrets.token_urlsafe(32))"`

2. **DATABASE_URL** (PostgreSQL)
   - Формат: `postgresql://user:password@host:port/database`
   - Пример: `postgresql://postgres:password@localhost:5432/haneat`

3. **REDIS_URL**
   - Пример: `redis://localhost:6379/0`

### Опциональные ключи

4. **OPENAI_API_KEY**
   - 🔗 Получить: https://platform.openai.com/api-keys
   - 🔗 Регистрация: https://platform.openai.com/signup

5. **SPOONACULAR_API_KEY**
   - 🔗 Получить: https://spoonacular.com/food-api/console
   - 🔗 Регистрация: https://spoonacular.com/food-api/console

6. **STRIPE ключи**
   - 🔗 Dashboard: https://dashboard.stripe.com
   - 🔗 Регистрация: https://dashboard.stripe.com/register
   - 🔗 API Keys: https://dashboard.stripe.com/apikeys
   - 🔗 Products: https://dashboard.stripe.com/products
   - 🔗 Webhooks: https://dashboard.stripe.com/webhooks

7. **FIREBASE ключи**
   - 🔗 Console: https://console.firebase.google.com
   - 🔗 Регистрация: https://console.firebase.google.com

8. **AWS S3 ключи**
   - 🔗 S3: https://aws.amazon.com/s3/
   - 🔗 IAM: https://console.aws.amazon.com/iam

---

## 📝 Инструкция по заполнению

### Минимум для запуска (backend/.env)

1. **SECRET_KEY**
   - Откройте: https://www.lastpass.com/features/password-generator
   - Установите длину: 32+ символов
   - Скопируйте и вставьте в `SECRET_KEY=...`

2. **DATABASE_URL**
   - Если PostgreSQL локально: `postgresql://postgres:ваш_пароль@localhost:5432/haneat`
   - Если через Docker: `postgresql://postgres:postgres@localhost:5432/haneat`

3. **REDIS_URL**
   - Если Redis локально: `redis://localhost:6379/0`
   - Если через Docker: `redis://localhost:6379/0`

### Опционально (можно добавить позже)

4. **OPENAI_API_KEY**
   - Перейдите: https://platform.openai.com/api-keys
   - Создайте ключ
   - Скопируйте в `OPENAI_API_KEY=sk-proj-...`

5. **SPOONACULAR_API_KEY** (.env в корне)
   - Перейдите: https://spoonacular.com/food-api/console
   - Зарегистрируйтесь
   - Создайте API ключ
   - Скопируйте в `SPOONACULAR_API_KEY=...`

---

## ✅ Проверка

После заполнения файлов:

**Backend:**
```bash
cd backend
python -c "from app.core.config import settings; print('✅ Config OK' if settings.SECRET_KEY else '❌ SECRET_KEY missing')"
```

**Frontend:**
```bash
flutter pub get
flutter run
```

---

## 🎯 Что дальше?

1. ✅ Запустите скрипт создания файлов
2. ✅ Откройте `backend/.env` и заполните обязательные переменные
3. ✅ (Опционально) Откройте `.env` и добавьте `SPOONACULAR_API_KEY`
4. ✅ Запустите приложение!

Все ссылки уже в файлах - просто переходите по 🔗 и копируйте ключи! 🚀

