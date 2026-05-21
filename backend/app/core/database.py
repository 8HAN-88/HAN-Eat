"""
Подключение к базе данных с оптимизированным connection pool
"""
from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)

def _create_engine():
    db_url = settings.DATABASE_URL
    is_sqlite = db_url.startswith("sqlite")

    if is_sqlite:
        # Локальный dev fallback без PostgreSQL.
        return create_engine(
            db_url,
            echo=settings.DEBUG,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )

    # Создаем engine с connection pool для production
    # Для 100k пользователей нужно ~200-500 одновременных соединений
    return create_engine(
        db_url,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_pre_ping=True,  # Проверка соединений перед использованием
        pool_recycle=settings.DB_POOL_RECYCLE,  # Переподключение для избежания таймаутов
        pool_timeout=settings.DB_POOL_TIMEOUT,
        echo=settings.DEBUG,
        connect_args={
            "connect_timeout": 10,
            "application_name": "haneat_backend"
        }
    )


engine = _create_engine()

# Логирование событий пула (только в DEBUG)
if settings.DEBUG:
    @event.listens_for(engine, "connect")
    def set_sqlite_pragma(dbapi_conn, connection_record):
        logger.debug("New database connection established")
    
    @event.listens_for(engine, "checkout")
    def receive_checkout(dbapi_conn, connection_record, connection_proxy):
        logger.debug("Connection checked out from pool")
    
    @event.listens_for(engine, "checkin")
    def receive_checkin(dbapi_conn, connection_record):
        logger.debug("Connection returned to pool")

# Session factory
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False  # Оптимизация: не обновлять объекты после commit
)

# Base для моделей
Base = declarative_base()


def ensure_channel_members_notifications_column() -> None:
    """SQLite/Postgres: добавить channel_members.notifications_enabled при обновлении схемы."""
    from sqlalchemy import inspect, text

    try:
        insp = inspect(engine)
        if "channel_members" not in insp.get_table_names():
            return
        cols = {c["name"] for c in insp.get_columns("channel_members")}
        if "notifications_enabled" in cols:
            return
        is_sqlite = str(engine.url).startswith("sqlite")
        with engine.begin() as conn:
            if is_sqlite:
                conn.execute(
                    text(
                        "ALTER TABLE channel_members ADD COLUMN "
                        "notifications_enabled BOOLEAN NOT NULL DEFAULT 1"
                    )
                )
            else:
                conn.execute(
                    text(
                        "ALTER TABLE channel_members ADD COLUMN "
                        "notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE"
                    )
                )
    except Exception as e:
        logger.warning("ensure_channel_members_notifications_column: %s", e)


def get_db():
    """Dependency для получения DB сессии"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

