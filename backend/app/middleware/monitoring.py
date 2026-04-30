"""
Middleware для мониторинга производительности
"""
import time
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)

class PerformanceMonitoringMiddleware(BaseHTTPMiddleware):
    """Middleware для отслеживания времени выполнения запросов"""
    
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        
        try:
            response = await call_next(request)
        except Exception as e:
            process_time = time.time() - start_time
            logger.error(
                f"Request error: {request.method} {request.url.path} "
                f"took {process_time:.2f}s - {str(e)}"
            )
            raise
        
        process_time = time.time() - start_time
        
        # Логируем медленные запросы (> 1 секунды)
        if process_time > 1.0:
            logger.warning(
                f"Slow request: {request.method} {request.url.path} "
                f"took {process_time:.2f}s"
            )
        elif process_time > 0.5:
            logger.info(
                f"Request: {request.method} {request.url.path} "
                f"took {process_time:.2f}s"
            )
        
        # Добавляем заголовок с временем выполнения
        response.headers["X-Process-Time"] = f"{process_time:.3f}"
        
        return response

