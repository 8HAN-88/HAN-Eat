# H.A.N. Eat Backend

Backend API для социальной платформы с рецептами и сообществами.

## Технологии

- **FastAPI** (Python) или **NestJS** (Node.js)
- **PostgreSQL** - основная БД
- **Redis** - кэш и очереди
- **S3-compatible Storage** - медиа файлы
- **RabbitMQ/Redis Streams** - очереди задач

## Миграции

После обновления кода примените миграции (в т.ч. `034_recipe_visibility_v1`, `035_channel_member_status_v1`, `036_email_auth_tokens_v1`):

```bash
cd backend
alembic upgrade head
```

## Структура проекта

```
backend/
├── app/
│   ├── api/
│   │   ├── v1/
│   │   │   ├── auth.py          # Аутентификация
│   │   │   ├── users.py         # Пользователи
│   │   │   ├── posts.py         # Публикации
│   │   │   ├── communities.py   # Сообщества
│   │   │   ├── feed.py          # Лента
│   │   │   ├── media.py         # Загрузка медиа
│   │   │   └── moderation.py    # Модерация
│   │   └── dependencies.py      # Зависимости (auth, db)
│   ├── core/
│   │   ├── config.py            # Конфигурация
│   │   ├── security.py          # JWT, хеширование
│   │   └── database.py           # Подключение к БД
│   ├── models/
│   │   ├── user.py
│   │   ├── post.py
│   │   ├── community.py
│   │   └── ...
│   ├── schemas/
│   │   ├── user.py              # Pydantic схемы
│   │   ├── post.py
│   │   └── ...
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── post_service.py
│   │   ├── feed_service.py
│   │   ├── moderation_service.py
│   │   └── media_service.py
│   ├── workers/
│   │   └── video_processor.py   # FFmpeg worker
│   └── main.py                   # Точка входа
├── migrations/                    # Alembic миграции
├── tests/
├── requirements.txt
└── .env.example
```

## Установка

```bash
# Создать виртуальное окружение
python -m venv venv
source venv/bin/activate  # или venv\Scripts\activate на Windows

# Установить зависимости
pip install -r requirements.txt

# Настроить .env файл
cp .env.example .env
# Отредактировать .env с вашими настройками

# Применить миграции
alembic upgrade head

# Запустить сервер
uvicorn app.main:app --reload
```

## Тестовые аккаунты

Пароль для всех: `HANtest2026!` — тарифы (free / AI / Creator / Pro), модераторы и админы.

```bash
python3 scripts/create_all_test_accounts.py
```

Полный список: [docs/TEST_ACCOUNTS.md](docs/TEST_ACCOUNTS.md)

## Переменные окружения

```env
# Database
DATABASE_URL=postgresql://user:password@localhost/haneat

# Redis
REDIS_URL=redis://localhost:6379

# JWT
SECRET_KEY=your-secret-key
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# S3
S3_BUCKET=haneat-media
S3_REGION=us-east-1
S3_ACCESS_KEY=...
S3_SECRET_KEY=...

# OpenAI (для модерации)
OPENAI_API_KEY=...

# Email (регистрация, сброс/смена пароля, смена email)
REQUIRE_EMAIL_VERIFICATION=true
AUTH_LINK_BASE_URL=haneat://auth
EMAIL_SMTP_HOST=smtp.example.com
EMAIL_SMTP_PORT=587
EMAIL_SMTP_USER=
EMAIL_SMTP_PASSWORD=
EMAIL_SMTP_USE_TLS=true
EMAIL_FROM=noreply@haneat.app
EMAIL_FROM_NAME=HAN Eat

# Queue
RABBITMQ_URL=amqp://localhost:5672
```

### Auth API (email)

| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/api/v1/auth/register` | Регистрация + письмо подтверждения |
| POST | `/api/v1/auth/login` | Вход (403 `EMAIL_NOT_VERIFIED`, если почта не подтверждена) |
| POST | `/api/v1/auth/verify-email` | `{ "token": "..." }` |
| POST | `/api/v1/auth/forgot-password` | `{ "email": "..." }` |
| POST | `/api/v1/auth/reset-password` | `{ "token", "new_password" }` |
| POST | `/api/v1/auth/change-password` | JWT + текущий и новый пароль |
| POST | `/api/v1/auth/change-email` | JWT + новый email и пароль |
| POST | `/api/v1/auth/confirm-email-change` | `{ "token": "..." }` |
| POST | `/api/v1/auth/resend-verification` | Повторное письмо (email в теле или JWT) |

Без SMTP в dev письма пишутся в лог сервера.

## API Документация

После запуска сервера:
- Swagger UI: http://localhost:5000/docs
- ReDoc: http://localhost:5000/redoc

## Тестирование

```bash
pytest tests/
```

## Деплой

См. `docs/DEPLOYMENT.md`

