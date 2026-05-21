"""
Подключение к Redis с пулом соединений для production
"""
import redis
from redis.connection import ConnectionPool
from redis.exceptions import ConnectionError, TimeoutError
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)


class _RedisStub:
    """Заглушка Redis: не подключается, все операции — no-op (для работы без Redis)."""

    def get(self, key):
        return None

    def set(self, key, value, ex=None, px=None, nx=False, **kwargs):
        if nx:
            return True
        pass

    def setex(self, name, time, value):
        pass

    def delete(self, *keys):
        pass

    def lpush(self, name, *values):
        pass

    def rpop(self, name):
        return None

    def incr(self, key, amount=1):
        if not hasattr(self, "_counts"):
            self._counts = {}
        self._counts[key] = self._counts.get(key, 0) + amount
        return self._counts[key]

    def expire(self, key, time):
        pass

    def ping(self):
        pass


# Инициализация Redis
redis_client = None

if not getattr(settings, "REDIS_ENABLED", True):
    redis_client = _RedisStub()
    logger.info("⚠️ Redis отключен (REDIS_ENABLED=false), работаем без кеша")
else:
    logger.info(f"Инициализация Redis с URL: {settings.REDIS_URL}")
    try:
        redis_pool = ConnectionPool.from_url(
            settings.REDIS_URL,
            max_connections=settings.REDIS_MAX_CONNECTIONS,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True,
            health_check_interval=30
        )
        redis_client = redis.Redis(connection_pool=redis_pool)
        try:
            redis_client.ping()
            logger.info("✅ Redis подключен успешно")
        except (ConnectionError, TimeoutError) as e:
            logger.error(f"❌ Ошибка подключения к Redis: {e}")
            logger.error(f"   URL: {settings.REDIS_URL}")
            redis_client = _RedisStub()
            logger.info("   → Переключение на режим без Redis")
    except Exception as e:
        logger.error(f"❌ Ошибка при создании Redis пула: {e}")
        logger.error(f"   URL: {settings.REDIS_URL}")
        redis_client = _RedisStub()
        logger.info("   → Переключение на режим без Redis")


def get_redis():
    """Dependency для получения Redis клиента"""
    return redis_client


REDIS_IS_STUB = isinstance(redis_client, _RedisStub)

