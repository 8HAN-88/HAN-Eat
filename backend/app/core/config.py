"""
Конфигурация приложения
"""
from pydantic_settings import BaseSettings
from pydantic import field_validator, model_validator
from typing import List, Optional, Union, Any


class Settings(BaseSettings):
    # App
    APP_NAME: str = "H.A.N. Eat API"
    APP_ENV: str = "development"
    DEBUG: bool = True
    # Разрешить POST /api/v1/subscriptions/create при APP_ENV=production (иначе только webhook’и оплаты)
    ALLOW_DIRECT_SUBSCRIPTION_CREATE: bool = False
    
    # Database
    DATABASE_URL: str = "postgresql://user:password@localhost:5432/haneat"
    
    # Database Connection Pool (для 100k пользователей)
    DB_POOL_SIZE: int = 20  # Базовый размер пула
    DB_MAX_OVERFLOW: int = 40  # Дополнительные соединения при нагрузке
    DB_POOL_RECYCLE: int = 3600  # Переподключение каждый час
    DB_POOL_TIMEOUT: int = 30  # Таймаут ожидания соединения
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_ENABLED: bool = True  # False = работать без Redis (медленнее, без кеша)
    REDIS_MAX_CONNECTIONS: int = 50  # Максимум соединений к Redis
    
    # JWT (в production задайте SECRET_KEY в .env; значение по умолчанию только для локального запуска)
    SECRET_KEY: str = "dev-only-change-with-SECRET_KEY-env-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # S3
    S3_BUCKET: str = "haneat-media"
    S3_REGION: str = "us-east-1"
    S3_ENDPOINT_URL: str = "https://s3.amazonaws.com"
    S3_ACCESS_KEY: str = ""
    S3_SECRET_KEY: str = ""
    
    # CDN
    CDN_URL: str = "https://cdn.haneat.com"
    
    # OpenAI
    OPENAI_API_KEY: str = ""
    # Vision для AI-скана (КБЖУ): дешевле и быстрее gpt-4o-mini
    OPENAI_FOOD_SCAN_MODEL: str = "gpt-4.1-nano"
    
    # Анализ фото (/analyze): авторизация обязательна; доступ по JWT ai_scan_ticket после POST /ai-scan/reserve.
    # Флаг ниже больше не используется в analyze_photo (оставлен для совместимости .env).
    REQUIRE_PLUS_FOR_PHOTO_ANALYSIS: bool = False

    # Модерация: премодерация при публикации (legacy, см. ENABLE_AI_MODERATION)
    ENABLE_PRE_MODERATION: bool = False
    # AI pipeline при публикации (текст + изображения): safe / warning / block
    ENABLE_AI_MODERATION: bool = True

    # Подписки (RUB, ЮKassa) — V1 тарифы
    AI_MONTHLY_PRICE_RUB: float = 199.0
    CREATOR_MONTHLY_PRICE_RUB: float = 499.0
    PRO_MONTHLY_PRICE_RUB: float = 649.0
    # Legacy aliases (совместимость)
    PLUS_MONTHLY_PRICE_RUB: float = 649.0
    PLUS_YEARLY_PRICE_RUB: float = 6490.0
    SUBSCRIPTION_TRIAL_DAYS: int = 7
    SUBSCRIPTION_GRACE_PERIOD_DAYS: int = 3
    # Окно для запроса возврата через поддержку (дней с даты оплаты)
    SUBSCRIPTION_REFUND_REQUEST_DAYS: int = 14
    
    # Spoonacular API (для рецептов)
    SPOONACULAR_API_KEY: str = ""
    
    # Google Sign-In (OAuth id_token): audiences из Cloud Console, через запятую; пусто = любой валидный aud от Google
    GOOGLE_OAUTH_CLIENT_IDS: str = ""
    # Только локальные тесты: не вызывать tokeninfo (небезопасно, в production всегда false)
    SKIP_GOOGLE_ID_TOKEN_VERIFICATION: bool = False

    # Яндекс ID (OAuth 2.0) — https://oauth.yandex.ru
    YANDEX_OAUTH_CLIENT_ID: str = ""
    YANDEX_OAUTH_CLIENT_SECRET: str = ""

    # Firebase (для FCM и APNs)
    FIREBASE_ENABLED: bool = False
    FIREBASE_CREDENTIALS_PATH: str = ""  # Путь к JSON файлу с credentials Firebase
    FIREBASE_PROJECT_ID: str = ""
    
    # Stripe (для платежей - для западных стран, пока отключено)
    STRIPE_ENABLED: bool = False
    STRIPE_SECRET_KEY: str = ""  # Stripe Secret Key
    STRIPE_PUBLISHABLE_KEY: str = ""  # Stripe Publishable Key (для frontend)
    STRIPE_WEBHOOK_SECRET: str = ""  # Stripe Webhook Secret для проверки подписи
    STRIPE_PRICE_ID_MONTHLY: str = ""  # Price ID для месячной подписки
    STRIPE_PRICE_ID_YEARLY: str = ""  # Price ID для годовой подписки
    
    # ЮKassa (для платежей в России, Беларуси, Казахстане - СБП, карты)
    YOOKASSA_ENABLED: bool = False
    YOOKASSA_SHOP_ID: str = ""  # Shop ID из личного кабинета ЮKassa
    YOOKASSA_SECRET_KEY: str = ""  # Secret Key из личного кабинета ЮKassa
    
    FRONTEND_URL: str = "http://localhost:8080"  # URL фронтенда для redirect после оплаты

    # Email-only auth: подтверждение почты, сброс/смена пароля, смена email
    REQUIRE_EMAIL_VERIFICATION: bool = True
    # Ссылки в письмах (в приложении — deep link haneat://auth/...)
    AUTH_LINK_BASE_URL: str = "haneat://auth"
    AUTH_VERIFY_EMAIL_HOURS: int = 48
    AUTH_RESET_PASSWORD_HOURS: int = 2
    AUTH_CHANGE_EMAIL_HOURS: int = 24

    EMAIL_SMTP_HOST: str = ""
    EMAIL_SMTP_PORT: int = 587
    EMAIL_SMTP_USER: str = ""
    EMAIL_SMTP_PASSWORD: str = ""
    EMAIL_SMTP_USE_TLS: bool = True
    EMAIL_SMTP_USE_SSL: bool = False
    EMAIL_FROM: str = ""
    EMAIL_FROM_NAME: str = "HAN Eat"
    # smtp (по умолчанию) или resend — HTTP API, обходит блокировки SMTP Яндекса с VPS
    EMAIL_PROVIDER: str = "smtp"
    RESEND_API_KEY: str = ""

    @field_validator(
        "EMAIL_SMTP_USER",
        "EMAIL_SMTP_PASSWORD",
        "EMAIL_FROM",
        "EMAIL_SMTP_HOST",
        mode="before",
    )
    @classmethod
    def _strip_email_env(cls, v: Any) -> Any:
        if isinstance(v, str):
            return v.strip()
        return v

    # Базовый URL API для ссылок на загруженные файлы без S3 (mock). Должен совпадать с портом uvicorn (часто 5001).
    API_PUBLIC_BASE_URL: str = "http://127.0.0.1:5001"
    
    # Queue
    RABBITMQ_URL: str = "amqp://localhost:5672"
    REDIS_STREAMS_ENABLED: bool = False
    
    # CORS
    # Для Flutter web нужно разрешить конкретные origins
    # В development разрешаем localhost на любых портах
    # Может быть задан как строка через запятую в .env или как список
    # Union[str, List[str]]: pydantic-settings парсит List из .env как JSON;
    # comma-separated строка без кавычек иначе падает при старте.
    ALLOWED_ORIGINS: Union[str, List[str]] = (
        "http://localhost:3000,"
        "http://localhost:8080,"
        "http://localhost:5000,"
        "http://127.0.0.1:5000"
    )

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def parse_allowed_origins(cls, value: Any) -> List[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(item).strip() for item in value if str(item).strip()]
        if isinstance(value, str):
            origins_str = value.strip()
            if not origins_str:
                return []
            if origins_str.startswith("["):
                import json

                parsed = json.loads(origins_str)
                if not isinstance(parsed, list):
                    raise ValueError("ALLOWED_ORIGINS JSON must be a list")
                return [str(item).strip() for item in parsed if str(item).strip()]
            return [origin.strip() for origin in origins_str.split(",") if origin.strip()]
        return list(value)

    @model_validator(mode='before')
    @classmethod
    def parse_env_values(cls, data: Any) -> Any:
        """Обрабатывает значения из .env до парсинга JSON"""
        if isinstance(data, dict):
            # Обрабатываем другие List поля
            for field in ['ALLOWED_IMAGE_TYPES', 'ALLOWED_VIDEO_TYPES']:
                if field in data and isinstance(data[field], str):
                    types_str = data[field].strip()
                    if types_str:
                        data[field] = [item.strip() for item in types_str.split(',') if item.strip()]
                    else:
                        data[field] = []
        return data
    
    # Rate Limiting (для 100k пользователей)
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_PER_MINUTE: int = 120  # Увеличено для production
    RATE_LIMIT_PER_HOUR: int = 5000
    RATE_LIMIT_BURST: int = 20  # Кратковременные всплески
    
    # Media
    MAX_IMAGE_SIZE_MB: int = 10
    MAX_VIDEO_SIZE_MB: int = 100
    ALLOWED_IMAGE_TYPES: List[str] = ["jpeg", "jpg", "png", "webp"]
    ALLOWED_VIDEO_TYPES: List[str] = ["mp4", "mov", "avi"]
    
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8-sig"  # UTF-8 с BOM или без, автоматически определяет
        case_sensitive = True
        extra = "ignore"  # Игнорировать дополнительные поля из .env


settings = Settings()

