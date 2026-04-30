# Запуск Backend сервера

## Быстрый старт

1. **Установите зависимости:**
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. **Настройте .env файл:**
Создайте файл `backend/.env` с настройками (см. SETUP.md)

3. **Настройте базу данных:**
```bash
# Создайте БД PostgreSQL
createdb haneat

# Примените миграции
alembic upgrade head
```

4. **Запустите Redis:**
```bash
redis-server
```

5. **Запустите сервер:**
```bash
# Вариант 1: через run.py
python run.py

# Вариант 2: через uvicorn
uvicorn app.main:app --reload --host 0.0.0.0 --port 5000
```

Сервер будет доступен по адресу: **http://localhost:5000**

API документация: **http://localhost:5000/docs**

## Проверка работы

Откройте в браузере:
- http://localhost:5000/health - должен вернуть `{"status": "ok"}`
- http://localhost:5000/docs - Swagger UI с документацией API

## Тестирование API

### Регистрация пользователя:
```bash
curl -X POST "http://localhost:5000/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "name": "Test User"
  }'
```

### Вход:
```bash
curl -X POST "http://localhost:5000/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### Получить профиль (нужен token):
```bash
curl -X GET "http://localhost:5000/api/v1/users/me" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

