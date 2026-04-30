# Быстрый старт разработки

## Шаг 1: Настройка окружения

### Backend

```bash
cd backend

# Создать виртуальное окружение
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Установить зависимости
pip install fastapi uvicorn sqlalchemy psycopg2-binary redis python-dotenv pydantic pydantic-settings

# Настроить .env
cp .env.example .env
# Отредактировать .env с вашими настройками БД и Redis

# Применить миграции (когда будут готовы)
alembic upgrade head

# Запустить сервер
uvicorn app.main:app --reload
```

### Frontend

```bash
cd mobile_app  # или где находится Flutter проект

# Установить зависимости
flutter pub get

# Запустить приложение
flutter run
```

## Шаг 2: Первый endpoint

Создайте файл `backend/app/api/v1/auth.py`:

```python
from fastapi import APIRouter, Depends
from app.schemas.auth import RegisterRequest, LoginRequest
from app.services.auth_service import AuthService

router = APIRouter()

@router.post("/register")
async def register(request: RegisterRequest):
    service = AuthService()
    user = await service.register(request.email, request.password, request.name)
    token = service.create_token(user.id)
    return {"user": user, "token": token}
```

## Шаг 3: Тестирование

```bash
# Запустить тесты
pytest tests/

# Или проверить API через Swagger
# Открыть http://localhost:5000/docs
```

## Следующие шаги

1. Реализовать базовую аутентификацию
2. Создать модели пользователей
3. Реализовать CRUD для постов
4. Настроить загрузку медиа
5. Реализовать ленту

См. `IMPLEMENTATION_CHECKLIST.md` для детального плана.

