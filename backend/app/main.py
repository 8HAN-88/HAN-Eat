"""
Главный файл приложения FastAPI
"""
import asyncio
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1 import auth, users, posts, feed, channels, communities, media, moderation, likes, comments, saved_posts, reposts, reports, analytics, notifications, subscriptions, support, search, payments, recipes, community_upload, ai_scan, creator, meal_plans, system, legal
from app.middleware.monitoring import PerformanceMonitoringMiddleware
from app.middleware.rate_limit import RateLimitMiddleware
from app.core.database import Base, engine
import app.models

logger = logging.getLogger(__name__)

_docs = "/docs" if settings.APP_ENV == "development" else None
_redoc = "/redoc" if settings.APP_ENV == "development" else None

app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    docs_url=_docs,
    redoc_url=_redoc,
)

# Мониторинг производительности (добавляем первым, чтобы отслеживать все запросы)
app.add_middleware(PerformanceMonitoringMiddleware)
app.add_middleware(RateLimitMiddleware)

# CORS
# В development режиме разрешаем все localhost origins для удобства разработки
# Flutter web может работать на разных портах (например, 51899, 51964 и т.д.)
if settings.APP_ENV == "development":
    # Используем allow_origin_regex для разрешения всех localhost портов
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    # В production используем строгий список origins
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Подключение роутеров
app.include_router(auth.router, prefix="/api/v1/auth", tags=["Auth"])
app.include_router(users.router, prefix="/api/v1/users", tags=["Users"])
app.include_router(posts.router, prefix="/api/v1/posts", tags=["Posts"])
app.include_router(feed.router, prefix="/api/v1/feed", tags=["Feed"])
app.include_router(channels.router, prefix="/api/v1/channels", tags=["Channels"])
app.include_router(
    communities.router,
    prefix="/api/v1/communities",
    tags=["Communities (legacy)"],
)
app.include_router(media.router, prefix="/api/v1/uploads", tags=["Media"])
app.include_router(moderation.router, prefix="/api/v1/moderation", tags=["Moderation"])
app.include_router(likes.router, prefix="/api/v1", tags=["Likes"])
app.include_router(comments.router, prefix="/api/v1", tags=["Comments"])
app.include_router(saved_posts.router, prefix="/api/v1", tags=["Saved Posts"])
app.include_router(reposts.router, prefix="/api/v1", tags=["Reposts"])
app.include_router(reports.router, prefix="/api/v1", tags=["Reports"])
app.include_router(analytics.router, prefix="/api/v1/analytics", tags=["Analytics"])
app.include_router(notifications.router, prefix="/api/v1/notifications", tags=["Notifications"])
app.include_router(subscriptions.router, prefix="/api/v1/subscriptions", tags=["Subscriptions"])
app.include_router(support.router, prefix="/api/v1/support", tags=["Support"])
app.include_router(search.router, prefix="/api/v1", tags=["Search"])
app.include_router(payments.router, prefix="/api/v1/payments", tags=["Payments"])
app.include_router(ai_scan.router, prefix="/api/v1/ai-scan", tags=["AI Scan"])
app.include_router(meal_plans.router, prefix="/api/v1/meal-plans", tags=["Meal Plans"])
# Роутер для рецептов с префиксом /api/v1
app.include_router(recipes.router, prefix="/api/v1", tags=["Recipes"])
app.include_router(community_upload.router, prefix="/api/v1", tags=["Community"])
app.include_router(creator.router, prefix="/api/v1/creator", tags=["Creator"])
app.include_router(system.router, prefix="/api/v1/system", tags=["System"])
app.include_router(legal.router, tags=["Legal"])


@app.get("/")
async def root():
    return {
        "message": "H.A.N. Eat API",
        "version": "1.0.0",
        "docs": "/docs"
    }


@app.get("/health")
async def health():
    from app.core.infrastructure_startup import infrastructure_status

    infra = infrastructure_status()
    db_ok = infra["database"]["ok"]
    redis_cfg = infra["redis"]
    redis_ok = True if not redis_cfg["enabled"] else redis_cfg["ok"]
    ok = db_ok and redis_ok
    return {
        "status": "ok" if ok else "degraded",
        "database": db_ok,
        "redis": redis_cfg,
    }


@app.on_event("startup")
async def startup_event():
    # Локально / SQLite: полный create_all может упасть (например ARRAY в PostgreSQL-моделях).
    # Postgres: обычно создаёт все таблицы. В любом случае гарантируем notification_preferences.
    if settings.APP_ENV == "development":
        try:
            Base.metadata.create_all(bind=engine)
        except Exception as e:
            logger.warning(
                "create_all incomplete (частичная схема или SQLite): %s",
                e,
            )
    try:
        from app.models.notification_preferences import NotificationPreferences

        NotificationPreferences.__table__.create(bind=engine, checkfirst=True)
    except Exception:
        logger.exception(
            "Не удалось создать таблицу notification_preferences — экран настроек уведомлений может падать"
        )
    try:
        from app.core.database import ensure_channel_members_notifications_column

        ensure_channel_members_notifications_column()
    except Exception:
        logger.exception("Колонка notifications_enabled в channel_members")

    from app.core.media_startup import log_media_readiness
    from app.core.payments_startup import log_payments_readiness
    from app.core.production_startup import log_production_readiness

    log_payments_readiness()
    log_media_readiness()
    log_production_readiness()
    asyncio.create_task(_background_maintenance_loop())


async def _background_maintenance_loop() -> None:
    """Публикация отложенных постов и обслуживание подписок."""
    from app.core.database import SessionLocal
    from app.core.maintenance_lock import try_acquire_maintenance_lock
    from app.core.redis_client import get_redis
    from app.services.post_publish_service import publish_due_scheduled_posts
    from app.services.subscription_maintenance_service import SubscriptionMaintenanceService

    while True:
        await asyncio.sleep(60)
        if not try_acquire_maintenance_lock(get_redis()):
            continue
        db = SessionLocal()
        try:
            published = publish_due_scheduled_posts(db)
            SubscriptionMaintenanceService(db).run()
            db.commit()
            if published:
                logger.info("Published %s scheduled posts", published)
        except Exception:
            db.rollback()
            logger.exception("Background maintenance loop error")
        finally:
            db.close()

