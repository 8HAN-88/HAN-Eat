# 🔗 Все ссылки для получения ключей и регистрации

## 📋 Быстрая навигация

Просто переходите по ссылкам и копируйте ключи в `.env` файлы!

---

## 🔴 ОБЯЗАТЕЛЬНЫЕ (без них не запустится)

### 1. SECRET_KEY (JWT ключ)

**🔗 Онлайн генератор:**
https://www.lastpass.com/features/password-generator

**Или через PowerShell:**
```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Что делать:**
1. Перейдите по ссылке
2. Установите длину: 32+ символов
3. Скопируйте сгенерированную строку
4. Вставьте в `backend/.env` → `SECRET_KEY=...`

---

### 2. DATABASE_URL (PostgreSQL)

**Если используете Docker (рекомендуется):**
- Просто используйте: `postgresql://postgres:postgres@localhost:5432/haneat`
- Пароль: `postgres` (стандартный)

**Если устанавливаете PostgreSQL локально:**

**🔗 Скачать PostgreSQL:**
https://www.postgresql.org/download/windows/

**🔗 Прямая ссылка (EnterpriseDB):**
https://www.enterprisedb.com/downloads/postgres-postgresql-downloads

**Что делать:**
1. Скачайте и установите PostgreSQL
2. При установке укажите пароль для пользователя `postgres`
3. Запомните этот пароль!
4. Вставьте в `backend/.env`:
   ```env
   DATABASE_URL=postgresql://postgres:ВАШ_ПАРОЛЬ@localhost:5432/haneat
   ```

**🔗 Если используете Docker:**
https://www.docker.com/products/docker-desktop

---

### 3. REDIS_URL

**Если используете Docker (рекомендуется):**
- Просто используйте: `redis://localhost:6379/0`
- Не нужно ничего настраивать отдельно

**Если устанавливаете Redis локально:**

**🔗 Memurai (Windows версия Redis):**
https://www.memurai.com/get-memurai

**🔗 Или через WSL2:**
- Установите WSL2: `wsl --install`
- В WSL: `sudo apt install redis-server`

**Что делать:**
1. Установите Redis (или используйте Docker)
2. Вставьте в `backend/.env`:
   ```env
   REDIS_URL=redis://localhost:6379/0
   ```

---

## 🟡 ВАЖНЫЕ (для оплаты подписок)

### 4. ЮKassa (для оплаты в России)

**🔗 Регистрация:**
https://yookassa.ru/join

**🔗 Личный кабинет (после регистрации):**
https://yookassa.ru/my

**🔗 Документация:**
https://yookassa.ru/developers/api

**Что делать:**
1. Зарегистрируйтесь: https://yookassa.ru/join
2. Заполните данные компании/ИП
3. Войдите в личный кабинет: https://yookassa.ru/my
4. Перейдите в **Настройки** → **API**
5. Скопируйте:
   - **Shop ID** (идентификатор магазина)
   - **Secret Key** (секретный ключ)
6. Вставьте в `backend/.env`:
   ```env
   YOOKASSA_ENABLED=true
   YOOKASSA_SHOP_ID=ваш_shop_id
   YOOKASSA_SECRET_KEY=ваш_secret_key
   ```

**🔗 Настройка webhook (после получения ключей):**
https://yookassa.ru/my → Настройки → Уведомления

---

## 🟢 ОПЦИОНАЛЬНЫЕ (можно добавить позже)

### 5. OPENAI_API_KEY (для модерации контента)

**🔗 Регистрация:**
https://platform.openai.com/signup

**🔗 Получить API ключ:**
https://platform.openai.com/api-keys

**🔗 Документация:**
https://platform.openai.com/docs

**Что делать:**
1. Зарегистрируйтесь: https://platform.openai.com/signup
2. Перейдите в API Keys: https://platform.openai.com/api-keys
3. Создайте новый ключ
4. Скопируйте ключ (начинается с `sk-proj-...`)
5. Вставьте в `backend/.env`:
   ```env
   OPENAI_API_KEY=sk-proj-ваш_ключ
   ```

**💡 Можно скопировать из `RecipeApp/.env` если там уже есть!**

---

### 6. SPOONACULAR_API_KEY (для поиска рецептов)

**🔗 Регистрация и получение ключа:**
https://spoonacular.com/food-api/console

**🔗 Документация:**
https://spoonacular.com/food-api/docs

**Что делать:**
1. Зарегистрируйтесь: https://spoonacular.com/food-api/console
2. Войдите в аккаунт
3. Перейдите в раздел **API Keys**
4. Создайте новый API ключ или используйте существующий
5. Скопируйте ключ
6. Вставьте в `.env` в корне проекта:
   ```env
   SPOONACULAR_API_KEY=ваш_ключ
   ```

**💡 Можно скопировать из `RecipeApp/.env` если там уже есть!**

---

### 7. Stripe (для оплаты в других странах - пока не нужно)

**🔗 Регистрация:**
https://dashboard.stripe.com/register

**🔗 Dashboard:**
https://dashboard.stripe.com

**🔗 API Keys:**
https://dashboard.stripe.com/apikeys

**🔗 Products (для создания цен):**
https://dashboard.stripe.com/products

**🔗 Webhooks:**
https://dashboard.stripe.com/webhooks

**Что делать (когда понадобится):**
1. Зарегистрируйтесь: https://dashboard.stripe.com/register
2. Получите ключи: https://dashboard.stripe.com/apikeys
3. Создайте продукты: https://dashboard.stripe.com/products
4. Настройте webhook: https://dashboard.stripe.com/webhooks

**Пока можно оставить пустым:**
```env
STRIPE_ENABLED=false
```

---

### 8. Firebase (для push уведомлений - опционально)

**🔗 Console:**
https://console.firebase.google.com

**🔗 Регистрация:**
https://console.firebase.google.com

**🔗 Документация:**
https://firebase.google.com/docs

**Что делать:**
1. Создайте проект: https://console.firebase.google.com
2. Перейдите в **Project Settings** → **Service Accounts**
3. Нажмите **Generate new private key**
4. Сохраните JSON файл
5. Укажите путь в `backend/.env`:
   ```env
   FIREBASE_ENABLED=true
   FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json
   FIREBASE_PROJECT_ID=ваш_project_id
   ```

---

### 9. AWS S3 (для хранения медиа - опционально)

**🔗 Регистрация AWS:**
https://aws.amazon.com

**🔗 S3:**
https://aws.amazon.com/s3/

**🔗 IAM (для получения ключей):**
https://console.aws.amazon.com/iam

**Что делать:**
1. Создайте аккаунт AWS: https://aws.amazon.com
2. Создайте S3 bucket
3. Создайте IAM пользователя с правами на S3
4. Получите Access Key и Secret Key: https://console.aws.amazon.com/iam
5. Вставьте в `backend/.env`:
   ```env
   S3_ACCESS_KEY=ваш_access_key
   S3_SECRET_KEY=ваш_secret_key
   ```

---

## 📝 Чек-лист: Что нужно сделать

### Обязательно:

- [ ] **SECRET_KEY** - сгенерировать: https://www.lastpass.com/features/password-generator
- [ ] **DATABASE_URL** - настроить PostgreSQL или использовать Docker
- [ ] **REDIS_URL** - настроить Redis или использовать Docker

### Для оплаты подписок:

- [ ] **YOOKASSA_SHOP_ID** - получить: https://yookassa.ru/my → Настройки → API
- [ ] **YOOKASSA_SECRET_KEY** - получить: https://yookassa.ru/my → Настройки → API

### Опционально (можно позже):

- [ ] **OPENAI_API_KEY** - получить: https://platform.openai.com/api-keys (или из RecipeApp/.env)
- [ ] **SPOONACULAR_API_KEY** - получить: https://spoonacular.com/food-api/console (или из RecipeApp/.env)
- [ ] **FIREBASE** - настроить: https://console.firebase.google.com
- [ ] **S3** - настроить: https://aws.amazon.com/s3/

---

## 🚀 Быстрый старт

### Шаг 1: Обязательные ключи

1. **SECRET_KEY:**
   - Перейдите: https://www.lastpass.com/features/password-generator
   - Скопируйте и вставьте в `backend/.env`

2. **DATABASE_URL и REDIS_URL:**
   - Используйте Docker (самый простой способ)
   - Скачайте Docker: https://www.docker.com/products/docker-desktop
   - Запустите: `docker-compose up -d`
   - Используйте стандартные значения в `.env`

### Шаг 2: Для оплаты (если нужно)

3. **ЮKassa:**
   - Зарегистрируйтесь: https://yookassa.ru/join
   - Получите ключи: https://yookassa.ru/my → Настройки → API
   - Вставьте в `backend/.env`

### Шаг 3: Опционально

4. **OPENAI_API_KEY:**
   - Скопируйте из `RecipeApp/.env` (если там есть)
   - Или получите новый: https://platform.openai.com/api-keys

5. **SPOONACULAR_API_KEY:**
   - Скопируйте из `RecipeApp/.env` (если там есть)
   - Или получите новый: https://spoonacular.com/food-api/console

---

## 💡 Полезные советы

1. **Используйте Docker** для PostgreSQL и Redis - не нужно ничего настраивать
2. **Копируйте ключи из RecipeApp/.env** - там уже могут быть OPENAI_API_KEY и SPOONACULAR_API_KEY
3. **ЮKassa обязателен** только если нужна оплата подписок
4. **Остальное опционально** - можно добавить позже

---

## 📚 Дополнительная документация

- `ENV_FILES_FINAL.md` - что должно быть в .env файлах
- `DATABASE_REDIS_SETUP.md` - настройка PostgreSQL и Redis
- `YOOKASSA_SBP_SETUP.md` - подробная настройка ЮKassa
- `QUICK_DATABASE_SETUP.md` - быстрая настройка через Docker

---

## ✅ Итого

**Минимум для запуска:**
1. SECRET_KEY → https://www.lastpass.com/features/password-generator
2. DATABASE_URL → используйте Docker или установите PostgreSQL
3. REDIS_URL → используйте Docker или установите Redis

**Для оплаты:**
4. ЮKassa → https://yookassa.ru/join

**Остальное можно добавить позже!** 🎉

