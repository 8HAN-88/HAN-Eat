# Инструкция по запуску Backend

## Проблема: "Failed to fetch" при регистрации

Эта ошибка означает, что backend сервер не запущен или недоступен.

## Как запустить Backend

### 1. Убедитесь, что PostgreSQL и Redis запущены

```bash
# Проверьте статус Docker контейнеров
docker-compose ps

# Если не запущены, запустите их
docker-compose up -d
```

### 2. Активируйте виртуальное окружение Python

```bash
# Windows PowerShell
.venv\Scripts\Activate.ps1

# Windows CMD
.venv\Scripts\activate.bat

# Linux/Mac
source .venv/bin/activate
```

### 3. Убедитесь, что установлены все зависимости

```bash
cd backend
pip install -r requirements.txt
```

### 4. Проверьте файл .env

Убедитесь, что файл `backend/.env` существует и содержит все необходимые переменные (см. `backend/env_template.txt`).

### 5. Запустите миграции базы данных (если нужно)

```bash
cd backend
alembic upgrade head
```

### 6. Запустите сервер

```bash
cd backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 5000
```

Или используйте скрипт запуска:

```bash
# Windows
python backend/run.py

# Linux/Mac
python3 backend/run.py
```

### 7. Проверьте, что сервер запущен

Откройте в браузере: http://localhost:5000/docs

Вы должны увидеть Swagger UI с документацией API.

## Проверка подключения

После запуска backend, попробуйте снова зарегистрироваться в приложении. Ошибка "Failed to fetch" должна исчезнуть.

## Решение проблем

### Порт 5000 занят

Если порт 5000 уже занят, измените порт в:
- `backend/app/main.py` (если там указан порт)
- Команде запуска: `uvicorn app.main:app --reload --host 0.0.0.0 --port 5001`
- `lib/services/auth_service.dart`: измените `baseUrl` на `http://localhost:5001/api/v1`

### База данных не подключена

Проверьте:
1. PostgreSQL запущен: `docker-compose ps`
2. `DATABASE_URL` в `.env` правильный
3. Пароль в `DATABASE_URL` совпадает с паролем в `docker-compose.yml`

### Redis не подключен

Проверьте:
1. Redis запущен: `docker-compose ps`
2. `REDIS_URL` в `.env` правильный

