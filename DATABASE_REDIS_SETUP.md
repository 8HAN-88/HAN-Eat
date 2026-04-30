# 🗄️ Настройка PostgreSQL и Redis

## 📋 Что нужно

Для запуска backend нужны:
1. **PostgreSQL** - база данных
2. **Redis** - кэш и очереди

---

## 🔍 Как проверить, установлены ли они

### PostgreSQL

**Windows (PowerShell):**
```powershell
# Проверить, установлен ли PostgreSQL
Get-Service -Name postgresql* -ErrorAction SilentlyContinue

# Или проверить через psql
psql --version
```

**Windows (CMD):**
```cmd
# Проверить службу
sc query postgresql*

# Или проверить версию
psql --version
```

### Redis

**Windows:**
```cmd
# Проверить, запущен ли Redis
redis-cli ping
```

Если команда не найдена - Redis не установлен.

---

## 📦 Вариант 1: Установка локально (Windows)

### PostgreSQL

#### Способ 1: Официальный установщик (рекомендуется)

1. **Скачайте PostgreSQL:**
   - 🔗 Скачать: https://www.postgresql.org/download/windows/
   - 🔗 Прямая ссылка: https://www.enterprisedb.com/downloads/postgres-postgresql-downloads

2. **Установите:**
   - Запустите установщик
   - При установке укажите:
     - **Порт:** 5432 (по умолчанию)
     - **Пароль для пользователя postgres:** запомните этот пароль!
     - **Локаль:** можно оставить по умолчанию

3. **Проверьте установку:**
   ```cmd
   psql -U postgres
   ```
   Введите пароль, который указали при установке.

4. **Создайте базу данных:**
   ```sql
   CREATE DATABASE haneat;
   \q
   ```

#### Способ 2: Через Chocolatey

```powershell
# Установите Chocolatey (если нет): https://chocolatey.org/install
choco install postgresql
```

### Redis

#### Способ 1: WSL2 (рекомендуется для Windows)

1. **Установите WSL2:**
   ```powershell
   wsl --install
   ```
   Перезагрузите компьютер.

2. **В WSL установите Redis:**
   ```bash
   sudo apt update
   sudo apt install redis-server
   sudo service redis-server start
   ```

3. **Проверьте:**
   ```bash
   redis-cli ping
   # Должно вернуть: PONG
   ```

#### Способ 2: Memurai (Windows-версия Redis)

1. **Скачайте Memurai:**
   - 🔗 Скачать: https://www.memurai.com/get-memurai
   - Это Windows-версия Redis

2. **Установите и запустите**

3. **Проверьте:**
   ```cmd
   redis-cli ping
   ```

#### Способ 3: Через Chocolatey

```powershell
choco install redis-64
```

---

## 🐳 Вариант 2: Docker (самый простой!)

Если у вас установлен Docker, это самый простой способ.

### Установка Docker

1. **Скачайте Docker Desktop:**
   - 🔗 Скачать: https://www.docker.com/products/docker-desktop
   - Установите и запустите

### Запуск PostgreSQL и Redis через Docker

Создайте файл `docker-compose.yml` в корне проекта:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: haneat-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: haneat
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: haneat-redis
    ports:
      - "6379:6379"
    restart: unless-stopped

volumes:
  postgres_data:
```

**Запуск:**
```cmd
docker-compose up -d
```

**Остановка:**
```cmd
docker-compose down
```

**Проверка:**
```cmd
docker ps
```

После этого используйте в `.env`:
```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0
```

---

## ☁️ Вариант 3: Облачные сервисы (для production)

### PostgreSQL

1. **Supabase** (бесплатный тариф)
   - 🔗 Регистрация: https://supabase.com
   - 🔗 Создать проект: https://app.supabase.com
   - После создания получите connection string

2. **Neon** (бесплатный тариф)
   - 🔗 Регистрация: https://neon.tech
   - Создайте проект и получите connection string

3. **Railway** (бесплатный тариф)
   - 🔗 Регистрация: https://railway.app
   - Создайте PostgreSQL сервис

### Redis

1. **Upstash** (бесплатный тариф)
   - 🔗 Регистрация: https://upstash.com
   - Создайте Redis database
   - Получите Redis URL

2. **Redis Cloud** (бесплатный тариф)
   - 🔗 Регистрация: https://redis.com/try-free/
   - Создайте database

---

## 🔧 Как найти параметры подключения

### PostgreSQL

#### Локальная установка

**Формат:** `postgresql://username:password@host:port/database`

**Обычные значения:**
- **username:** `postgres` (по умолчанию)
- **password:** тот, который указали при установке
- **host:** `localhost` (если локально)
- **port:** `5432` (по умолчанию)
- **database:** `haneat` (нужно создать)

**Пример:**
```env
DATABASE_URL=postgresql://postgres:мой_пароль@localhost:5432/haneat
```

#### Облачный сервис

Обычно выдают готовый connection string, например:
```
postgresql://user:pass@host.region.provider.com:5432/dbname
```

Просто скопируйте его в `.env`.

### Redis

#### Локальная установка

**Формат:** `redis://host:port/db`

**Обычные значения:**
- **host:** `localhost`
- **port:** `6379` (по умолчанию)
- **db:** `0` (по умолчанию)

**Пример:**
```env
REDIS_URL=redis://localhost:6379/0
```

#### Облачный сервис

Обычно выдают готовый URL, например:
```
redis://default:password@host:port
```

Просто скопируйте его в `.env`.

---

## ✅ Проверка подключения

### PostgreSQL

**Через psql:**
```cmd
psql -U postgres -d haneat
```

Если подключилось - всё работает!

**Через Python:**
```python
import psycopg2
conn = psycopg2.connect("postgresql://postgres:password@localhost:5432/haneat")
print("✅ Подключение успешно!")
conn.close()
```

### Redis

**Через redis-cli:**
```cmd
redis-cli ping
```

Должно вернуть: `PONG`

**Через Python:**
```python
import redis
r = redis.from_url("redis://localhost:6379/0")
print(r.ping())  # Должно вернуть True
```

---

## 🚀 Быстрый старт (рекомендуется)

### Для разработки - используйте Docker:

1. **Установите Docker Desktop:**
   - 🔗 https://www.docker.com/products/docker-desktop

2. **Создайте `docker-compose.yml`** (я создам его ниже)

3. **Запустите:**
   ```cmd
   docker-compose up -d
   ```

4. **В `backend/.env` укажите:**
   ```env
   DATABASE_URL=postgresql://postgres:postgres@localhost:5432/haneat
   REDIS_URL=redis://localhost:6379/0
   ```

5. **Создайте базу данных:**
   ```cmd
   docker exec -it haneat-postgres psql -U postgres -c "CREATE DATABASE haneat;"
   ```

Готово! 🎉

---

## 📝 Создание базы данных

После установки PostgreSQL нужно создать базу данных:

**Через psql:**
```cmd
psql -U postgres
```

В psql выполните:
```sql
CREATE DATABASE haneat;
\q
```

**Или через командную строку:**
```cmd
psql -U postgres -c "CREATE DATABASE haneat;"
```

---

## 🔍 Поиск параметров подключения

### Если забыли пароль PostgreSQL

**Windows:**
1. Откройте "Службы" (Services)
2. Найдите "postgresql-x64-XX"
3. Остановите службу
4. Откройте файл `pg_hba.conf` (обычно в `C:\Program Files\PostgreSQL\XX\data\`)
5. Измените метод аутентификации на `trust`
6. Запустите службу
7. Подключитесь без пароля и измените пароль:
   ```sql
   ALTER USER postgres PASSWORD 'новый_пароль';
   ```

### Если не знаете порт

**PostgreSQL:**
- По умолчанию: `5432`
- Проверить: `netstat -an | findstr 5432`

**Redis:**
- По умолчанию: `6379`
- Проверить: `netstat -an | findstr 6379`

---

## 💡 Рекомендации

### Для разработки:
- ✅ Используйте Docker (самый простой способ)
- ✅ Или локальную установку PostgreSQL + Redis через WSL2

### Для production:
- ✅ Используйте облачные сервисы (Supabase, Neon, Upstash)
- ✅ Или собственный сервер с PostgreSQL и Redis

---

## 🆘 Проблемы и решения

### PostgreSQL не запускается

**Решение:**
```cmd
# Проверить службу
sc query postgresql*

# Запустить службу
net start postgresql-x64-XX
```

### Redis не запускается

**Решение (WSL2):**
```bash
sudo service redis-server start
```

**Решение (Memurai):**
- Проверьте службу "Memurai" в Services
- Запустите её

### Порт занят

**Решение:**
- Измените порт в конфигурации
- Или остановите другое приложение, использующее порт

---

## 📚 Дополнительные ресурсы

- 🔗 PostgreSQL документация: https://www.postgresql.org/docs/
- 🔗 Redis документация: https://redis.io/docs/
- 🔗 Docker документация: https://docs.docker.com/

