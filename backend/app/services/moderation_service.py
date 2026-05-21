"""
Сервис для модерации контента (OpenAI Moderation API + эвристики).
"""
import base64
import logging
from typing import Any, Dict, List, Optional

import openai

from app.core.config import settings

logger = logging.getLogger(__name__)


class ModerationService:
    """Автоматическая модерация текста и изображений."""

    def __init__(self):
        self.client = None
        if settings.OPENAI_API_KEY:
            try:
                self.client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)
            except Exception as e:
                logger.warning("OpenAI client init failed: %s", e)

    def check_text(self, text: str) -> Dict[str, Any]:
        if not text or not text.strip():
            return self._safe_result()

        if not self.client:
            return self._safe_result()

        try:
            response = self.client.moderations.create(input=text)
            result = response.results[0]

            if result.flagged:
                categories = result.categories
                category_scores = result.category_scores
                max_score = 0.0
                main_category = None
                for category in dir(categories):
                    if category.startswith("_"):
                        continue
                    if getattr(categories, category, False):
                        score = float(getattr(category_scores, category, 0.0) or 0.0)
                        if score > max_score:
                            max_score = score
                            main_category = category
                return {
                    "flagged": True,
                    "score": max_score,
                    "reason": main_category or "inappropriate",
                }
            return self._safe_result()
        except Exception as e:
            logger.warning("Moderation API error: %s", e)
            return self._safe_result()

    def check_image_url(self, image_url: str) -> float:
        """
        NSFW-оценка изображения (0..1). Без ключа — 0.
        V1: OpenAI vision low-detail при наличии ключа.
        """
        if not image_url or not self.client:
            return 0.0
        try:
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=80,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Rate this image for NSFW/adult content only. "
                                    "Reply JSON only: {\"nsfw_score\": 0.0 to 1.0}"
                                ),
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": image_url, "detail": "low"},
                            },
                        ],
                    }
                ],
            )
            import json
            import re

            raw = (response.choices[0].message.content or "").strip()
            if raw.startswith("```"):
                raw = re.sub(r"^```\w*\n?", "", raw).replace("```", "").strip()
            data = json.loads(raw)
            return min(1.0, max(0.0, float(data.get("nsfw_score", 0))))
        except Exception as e:
            logger.debug("Image moderation skipped for %s: %s", image_url[:60], e)
            return 0.0

    def check_image_bytes(self, image_bytes: bytes) -> float:
        if not image_bytes or not self.client:
            return 0.0
        b64 = base64.b64encode(image_bytes).decode("ascii")
        return self.check_image_url(f"data:image/jpeg;base64,{b64}")

    def should_moderate(self, text: str, title: Optional[str] = None) -> bool:
        full_text = f"{title or ''} {text}".strip()
        if not full_text:
            return False
        return bool(self.check_text(full_text).get("flagged"))

    def get_moderation_reason(self, text: str, title: Optional[str] = None) -> Optional[str]:
        full_text = f"{title or ''} {text}".strip()
        result = self.check_text(full_text)
        if result.get("flagged"):
            return result.get("reason")
        return None

    @staticmethod
    def _safe_result() -> Dict[str, Any]:
        return {"flagged": False, "score": 0.0, "reason": None}
