"""
Сервис для определения страны пользователя
"""
import logging
from typing import Optional
from fastapi import Request

logger = logging.getLogger(__name__)


class CountryService:
    """Сервис для определения страны пользователя"""
    
    # Страны, где доступна оплата через СБП/ЮKassa
    SUPPORTED_COUNTRIES = ["RU", "BY", "KZ"]  # Россия, Беларусь, Казахстан
    
    @staticmethod
    def get_country_from_request(request: Request) -> str:
        """
        Определить страну пользователя из запроса
        
        Приоритет:
        1. Заголовок Accept-Language (язык)
        2. IP адрес (если доступен)
        3. По умолчанию: RU (Россия)
        
        Args:
            request: FastAPI Request объект
            
        Returns:
            Код страны (ISO 3166-1 alpha-2), например "RU"
        """
        # 1. Проверяем заголовок Accept-Language
        accept_language = request.headers.get("Accept-Language", "")
        if accept_language:
            # Парсим язык (например, "ru-RU,ru;q=0.9" -> "ru")
            lang = accept_language.split(",")[0].split(";")[0].split("-")[0].lower()
            
            # Маппинг языков на страны
            lang_to_country = {
                "ru": "RU",
                "en": "US",  # По умолчанию для английского
                "uk": "UA",
                "kk": "KZ",
                "be": "BY",
            }
            
            if lang in lang_to_country:
                return lang_to_country[lang]
        
        # 2. Можно добавить определение по IP (требует внешний сервис)
        # Для простоты пока используем язык или дефолт
        
        # 3. По умолчанию - Россия
        return "RU"
    
    @staticmethod
    def is_supported_country(country_code: str) -> bool:
        """
        Проверить, поддерживается ли страна для оплаты
        
        Args:
            country_code: Код страны (ISO 3166-1 alpha-2)
            
        Returns:
            True если страна поддерживается
        """
        return country_code.upper() in CountryService.SUPPORTED_COUNTRIES
    
    @staticmethod
    def get_payment_provider_for_country(country_code: str) -> str:
        """
        Получить платежный провайдер для страны
        
        Args:
            country_code: Код страны
            
        Returns:
            Название провайдера: "yookassa" | "stripe" | "none"
        """
        country_code = country_code.upper()
        
        if country_code in ["RU", "BY", "KZ"]:
            return "yookassa"  # ЮKassa с поддержкой СБП
        elif country_code in ["US", "GB", "CA", "AU", "NZ", "IE"]:
            return "stripe"  # Stripe для западных стран (пока отключено)
        else:
            return "none"  # Пока не поддерживается

