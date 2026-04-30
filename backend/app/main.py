"""
Главный файл приложения FastAPI
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1 import auth, users, posts, feed, channels, media, moderation, likes, comments, saved_posts, reposts, reports, analytics, notifications, subscriptions, support, search, payments, recipes, community_upload
from app.middleware.monitoring import PerformanceMonitoringMiddleware

app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Мониторинг производительности (добавляем первым, чтобы отслеживать все запросы)
app.add_middleware(PerformanceMonitoringMiddleware)

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
# Роутер для рецептов с префиксом /api/v1
app.include_router(recipes.router, prefix="/api/v1", tags=["Recipes"])
app.include_router(community_upload.router, prefix="/api/v1", tags=["Community"])


@app.get("/")
async def root():
    return {
        "message": "H.A.N. Eat API",
        "version": "1.0.0",
        "docs": "/docs"
    }


@app.get("/health")
async def health():
    return {"status": "ok"}

