# Быстрое решение ошибки подключения к PostgreSQL

## Проблема
```
psycopg2.OperationalError: connection to server at "localhost" (::1), port 5432 failed: Connection refused
```

Это означает, что PostgreSQL не запущен или недоступен.

## Решение 1: Запуск через Docker (РЕКОМЕНДУЕТСЯ)

1. **Убедитесь, что Docker Desktop запущен**

2. **Запустите PostgreSQL и Redis:**
   ```powershell
   # Из корневой папки проекта (D:\HAN Eat 1)
   docker-compose up -d
   ```

3. **Проверьте, что контейнеры запущены:**
   ```powershell
   docker ps
   ```
   Должны быть видны контейнеры `haneat-postgres` и `haneat-redis`

4. **Примените миграции базы данных:**
   ```powershell
   cd backend
   alembic upgrade head
   ```

5. **Запустите сервер:**
   ```powershell
   python run.py
   ```

## Решение 2: Установка PostgreSQL локально

Если Docker недоступен:

1. **Скачайте и установите PostgreSQL:**
   - https://www.postgresql.org/download/windows/
   - Или через Chocolatey: `choco install postgresql`

2. **Создайте базу данных:**
   ```powershell
   # Запустите psql (обычно в C:\Program Files\PostgreSQL\15\bin\psql.exe)
   psql -U postgres
   CREATE DATABASE haneat;
   \q
   ```

3. **Обновите .env файл:**
   Убедитесь, что в `backend/.env` правильные настройки:
   ```env
   DATABASE_URL=postgresql://postgres:ВАШ_ПАРОЛЬ@localhost:5432/haneat
   ```

4. **Примените миграции:**
   ```powershell
   cd backend
   alembic upgrade head
   ```

5. **Запустите сервер:**
   ```powershell
   python run.py
   ```

## Проверка подключения

После запуска PostgreSQL, проверьте подключение:
```powershell
# Если используете Docker:
docker exec -it haneat-postgres psql -U postgres -d haneat

# Если локальная установка:
psql -U postgres -d haneat
```

Если подключение успешно, вы увидите приглашение `haneat=#`

## Остановка Docker контейнеров

Когда закончите работу:
```powershell
docker-compose down
```

Или для остановки с удалением данных:
```powershell
docker-compose down -v
```

