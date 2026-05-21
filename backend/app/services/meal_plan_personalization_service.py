"""Один вызов GPT (или rule-based fallback) для персонализации плана."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import settings
from app.schemas.meal_plan import NutritionPreferences

logger = logging.getLogger(__name__)


class MealPlanPersonalizationService:
    def build_strategy(
        self,
        preferences: NutritionPreferences,
        *,
        duration_days: int,
        tier: str,
    ) -> Dict[str, Any]:
        # Free: только rule-based nutrition strategy (без GPT — unit economics).
        if tier == "free":
            return self._fallback_strategy(preferences, duration_days=duration_days)
        if settings.OPENAI_API_KEY:
            gpt = self._gpt_strategy(preferences, duration_days=duration_days, tier=tier)
            if gpt:
                return gpt
        return self._fallback_strategy(preferences, duration_days=duration_days)

    def _fallback_strategy(
        self,
        preferences: NutritionPreferences,
        *,
        duration_days: int,
    ) -> Dict[str, Any]:
        daily = preferences.daily_calories or 2000
        diets = preferences.diets or []
        rec = "Сбалансированный рацион с акцентом на регулярные приёмы пищи и контроль порций."
        if any("Кето" in d or "кето" in d.lower() for d in diets):
            rec = "Рекомендуется умеренный белок и полезные жиры, минимум быстрых углеводов для стабильной энергии."
        elif any("Вегетариан" in d for d in diets):
            rec = "Рекомендуется сочетать растительный белок и цельные злаки для полноценного дня."
        elif any("Веган" in d for d in diets):
            rec = "Рекомендуется разнообразие бобовых, орехов и овощей для покрытия белка и микроэлементов."
        elif daily <= 1600:
            rec = "Рекомендуется белковый завтрак для поддержания энергии и контроля аппетита."
        elif daily >= 2400:
            rec = "Рекомендуется равномерно распределить калории между основными приёмами пищи."

        return {
            "ai_recommendation": rec,
            "daily_calorie_target": daily,
            "macro_split": {"protein_pct": 30, "fat_pct": 30, "carbs_pct": 40},
            "meal_timing_notes": "Завтрак в течение 2 часов после пробуждения, ужин за 3 часа до сна.",
            "duration_days": duration_days,
            "source": "rules",
        }

    def _gpt_strategy(
        self,
        preferences: NutritionPreferences,
        *,
        duration_days: int,
        tier: str,
    ) -> Optional[Dict[str, Any]]:
        prompt = {
            "duration_days": duration_days,
            "daily_calories": preferences.daily_calories,
            "diets": preferences.diets,
            "allergies": preferences.allergies,
            "diet_type": preferences.diet_type,
            "budget_level": preferences.budget_level,
            "meal_preferences": preferences.meal_preferences,
            "family_size": preferences.family_size,
            "tier": tier,
        }
        system = (
            "Ты нутрициолог H.A.N. Eat. Верни ТОЛЬКО JSON без markdown: "
            '{"ai_recommendation":"одна фраза на русском",'
            '"daily_calorie_target":число,'
            '"macro_split":{"protein_pct":30,"fat_pct":30,"carbs_pct":40},'
            '"meal_timing_notes":"кратко на русском"}. '
            "Не генерируй рецепты и не перечисляй блюда по дням."
        )
        try:
            with httpx.Client(timeout=25.0) as client:
                resp = client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "temperature": 0.4,
                        "max_tokens": 280,
                        "messages": [
                            {"role": "system", "content": system},
                            {
                                "role": "user",
                                "content": f"Профиль: {json.dumps(prompt, ensure_ascii=False)}",
                            },
                        ],
                    },
                )
            if resp.status_code != 200:
                logger.warning("meal plan GPT status %s", resp.status_code)
                return None
            content = resp.json()["choices"][0]["message"]["content"]
            data = json.loads(content.strip())
            if not isinstance(data, dict):
                return None
            data["source"] = "gpt"
            data["duration_days"] = duration_days
            if preferences.daily_calories and not data.get("daily_calorie_target"):
                data["daily_calorie_target"] = preferences.daily_calories
            return data
        except Exception as e:
            logger.warning("meal plan GPT failed: %s", e)
            return None
