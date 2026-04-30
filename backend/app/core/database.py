"""
Подключение к базе данных с оптимизированным connection pool
"""
from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)

# Создаем engine с connection pool для production
# Для 100k пользователей нужно ~200-500 одновременных соединений
engine = create_engine(
    settings.DATABASE_URL,
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


def get_db():
    """Dependency для получения DB сессии"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

