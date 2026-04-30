"""
Сервис для модерации контента
"""
import openai
from typing import Optional, Dict, Any
from app.core.config import settings


class ModerationService:
    """Сервис для автоматической модерации контента"""
    
    def __init__(self):
        self.client = None
        if settings.OPENAI_API_KEY:
            try:
                self.client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)
            except Exception as e:
                print(f"Warning: Failed to initialize OpenAI client: {e}")
    
    def check_text(self, text: str) -> Dict[str, Any]:
        """
        Проверить текст на токсичность через OpenAI Moderation API
        
        Returns:
            {
                "flagged": bool,
                "categories": {...},
                "score": float,
                "reason": str
            }
        """
        if not self.client:
            # Если OpenAI не настроен, пропускаем проверку (для разработки)
            return {
                "flagged": False,
                "categories": {},
                "score": 0.0,
                "reason": None
            }
        
        try:
            response = self.client.moderations.create(input=text)
            result = response.results[0]
            
            if result.flagged:
                # Определяем основную категорию
                categories = result.categories
                category_scores = result.category_scores
                
                # Находим категорию с максимальным score
                max_score = 0.0
                main_category = None
                for category, flagged in categories.__dict__.items():
                    if flagged:
                        score = getattr(category_scores, category, 0.0)
                        if score > max_score:
                            max_score = score
                            main_category = category
                
                return {
                    "flagged": True,
                    "categories": {k: getattr(categories, k, False) for k in dir(categories) if not k.startswith('_')},
                    "score": max_score,
                    "reason": main_category or "inappropriate"
                }
            else:
                return {
                    "flagged": False,
                    "categories": {},
                    "score": 0.0,
                    "reason": None
                }
        except Exception as e:
            print(f"Error in moderation check: {e}")
            # В случае ошибки пропускаем проверку (можно логировать)
            return {
                "flagged": False,
                "categories": {},
                "score": 0.0,
                "reason": None
            }
    
    def should_moderate(self, text: str, title: Optional[str] = None) -> bool:
        """
        Определить, нужна ли модерация контента
        
        Returns:
            True если нужна модерация, False если можно публиковать сразу
        """
        full_text = f"{title or ''} {text}".strip()
        
        if not full_text:
            return False
        
        result = self.check_text(full_text)
        
        # Если текст помечен как проблемный, нужна модерация
        if result["flagged"]:
            return True
        
        # Дополнительные правила (например, длинные тексты, определенные слова)
        # Пока возвращаем False для всех новых пользователей
        # В продакшене можно добавить проверку репутации пользователя
        
        return False
    
    def get_moderation_reason(self, text: str, title: Optional[str] = None) -> Optional[str]:
        """Получить причину модерации"""
        full_text = f"{title or ''} {text}".strip()
        result = self.check_text(full_text)
        
        if result["flagged"]:
            return result["reason"]
        
        return None

