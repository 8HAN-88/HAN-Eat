# 📦 Установка PostgreSQL и Redis локально (без Docker)

## 🎯 Шаг 1: Установка PostgreSQL

### Вариант A: Через официальный установщик (рекомендуется)

1. **Скачайте PostgreSQL:**
   - 🔗 **Официальный сайт:** https://www.postgresql.org/download/windows/
   - 🔗 **Прямая ссылка:** https://www.enterprisedb.com/downloads/postgres-postgresql-downloads
   - Выберите версию **PostgreSQL 15** или новее

2. **Установите PostgreSQL:**
   - Запустите установщик
   - **Важно:** Запомните пароль, который укажете для пользователя `postgres`!
   - Порт: оставьте **5432** (по умолчанию)
   - Локаль: можно оставить по умолчанию

3. **Проверьте установку:**
   ```powershell
   psql --version
   ```

### Вариант B: Через Chocolatey (если установлен)

```powershell
# Установить PostgreSQL
choco install postgresql

# После установки создайте базу данных
psql -U postgres -c "CREATE DATABASE haneat;"
```

---

## 🎯 Шаг 2: Создание базы данных

После установки PostgreSQL:

1. **Откройте psql:**
   ```powershell
   psql -U postgres
   ```
   Введите пароль, который указали при установке.

2. **Создайте базу данных:**
   ```sql
   CREATE DATABASE haneat;
   \q
   ```

3. **Проверьте создание:**
   ```powershell
   psql -U postgres -d haneat
   ```
   Если подключилось - всё работает!

---

## 🎯 Шаг 3: Установка Redis (опционально, но рекомендуется)

**Если Redis/Memurai не установлен** — в `backend/.env` добавьте `REDIS_ENABLED=false`. Backend будет работать без кеша (медленнее).

### Вариант A: Memurai (Windows-версия Redis)

1. **Скачайте Memurai:**
   - 🔗 **Скачать:** https://www.memurai.com/get-memurai
   - Это официальная Windows-версия Redis

2. **Установите и запустите:**
   - Запустите установщик
   - Memurai установится как служба Windows

3. **Проверьте:**
   ```powershell
   redis-cli ping
   ```
   Должно вернуть: `PONG`

### Вариант B: Redis через WSL (если WSL установлен)

```bash
# В WSL
sudo apt update
sudo apt install redis-server
sudo service redis-server start
```

---

## 🎯 Шаг 4: Настройка backend/.env

Создайте или обновите файл `backend/.env`:

```env
# JWT Secret Key
SECRET_KEY=BB2hzXR8k5ctP7nu5lzjYFW8dcVcYCC9qyo9jik1B3g

# PostgreSQL (используйте ВАШ пароль, который указали при установке!)
DATABASE_URL=postgresql://postgres:ВАШ_ПАРОЛЬ@localhost:5432/haneat

# Redis (если не установлен — поставьте REDIS_ENABLED=false)
REDIS_URL=redis://localhost:6379/0
REDIS_ENABLED=true

# Настройки приложения
APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000,http://127.0.0.1:5000
```

**⚠️ ВАЖНО:** Замените `ВАШ_ПАРОЛЬ` на пароль, который вы указали при установке PostgreSQL!

---

## ✅ Шаг 5: Проверка подключения

### PostgreSQL:

```powershell
# Проверить подключение
psql -U postgres -d haneat

# Если подключилось - всё работает!
# Выйти: \q
```

### Redis:

```powershell
# Проверить Redis
redis-cli ping
# Должно вернуть: PONG
```

---

## 🚀 Шаг 6: Запуск backend

После настройки:

```powershell
cd backend
python run.py
```

Backend должен подключиться к локальной базе данных!

---

## 🆘 Решение проблем

### PostgreSQL не запускается

```powershell
# Проверить службу
Get-Service -Name postgresql*

# Запустить службу (замените XX на версию)
Start-Service postgresql-x64-15
```

Или через "Службы" (Services):
1. Нажмите `Win + R`
2. Введите: `services.msc`
3. Найдите `postgresql-x64-XX`
4. Запустите службу

### Забыли пароль PostgreSQL

1. Откройте "Службы" (Services)
2. Найдите "postgresql-x64-XX"
3. Остановите службу
4. Откройте файл `pg_hba.conf` (обычно в `C:\Program Files\PostgreSQL\XX\data\`)
5. Найдите строку с `md5` и замените на `trust`
6. Запустите службу
7. Подключитесь без пароля:
   ```sql
   psql -U postgres
   ALTER USER postgres PASSWORD 'новый_пароль';
   ```
8. Верните `md5` обратно в `pg_hba.conf`
9. Перезапустите службу

### Порт 5432 занят

```powershell
# Проверить, что использует порт
netstat -ano | findstr :5432

# Если занят другим процессом, либо остановите его, либо измените порт PostgreSQL
```

---

## 📚 Полезные ссылки

- 🔗 **PostgreSQL документация:** https://www.postgresql.org/docs/
- 🔗 **Memurai (Redis для Windows):** https://www.memurai.com/
- 🔗 **Chocolatey:** https://chocolatey.org/

---

## 🎯 Быстрая установка (если есть Chocolatey)

```powershell
# Установить PostgreSQL
choco install postgresql

# Установить Memurai (Redis)
choco install memurai-developer

# После установки создайте базу данных
psql -U postgres -c "CREATE DATABASE haneat;"
```

---

**Готово! Теперь PostgreSQL работает локально без Docker! 🎉**


