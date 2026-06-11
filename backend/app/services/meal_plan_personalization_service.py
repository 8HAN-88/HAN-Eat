"""Один вызов GPT (или rule-based fallback) для персонализации плана."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import settings
from app.schemas.meal_plan import NutritionPreferences

logger = logging.getLogger(__name__)

_DEFAULT_MACRO_SPLIT = {"protein_pct": 30, "fat_pct": 30, "carbs_pct": 40}
_DEFAULT_MEAL_DISTRIBUTION = {"breakfast": 0.25, "lunch": 0.4, "dinner": 0.35}


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

        goal = preferences.primary_goal or ""
        if goal == "weight_loss":
            rec = "Умеренный дефицит калорий, белок в каждом приёме и регулярные перекусы помогут снизить вес без срывов."
        elif goal == "muscle_gain":
            rec = "Достаточный белок и калории после тренировок — основа набора мышечной массы."
        elif goal == "family":
            rec = "Универсальные блюда с понятными порциями удобны для всей семьи."
        elif goal == "more_energy":
            rec = "Сбалансированные углеводы и белок утром и днём поддержат стабильную энергию."
        elif goal == "health":
            rec = "Акцент на цельные продукты, овощи и умеренные порции улучшит самочувствие."

        targets = preferences.goal_targets or []
        if targets:
            rec = f"{rec} Учитываем ваши подцели: {', '.join(_goal_target_labels(targets))}."

        return {
            "ai_recommendation": rec,
            "daily_calorie_target": daily,
            "macro_split": dict(_DEFAULT_MACRO_SPLIT),
            "meal_calorie_distribution": dict(_DEFAULT_MEAL_DISTRIBUTION),
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
            "primary_goal": preferences.primary_goal,
            "activity_level": preferences.activity_level,
            "sex": preferences.sex,
            "age": preferences.age,
            "height_cm": preferences.height_cm,
            "weight_kg": preferences.weight_kg,
            "meals_per_day": preferences.meals_per_day,
            "cooking_time": preferences.cooking_time,
            "cooking_skill": preferences.cooking_skill,
            "weight_pace": preferences.weight_pace,
            "health_focus": preferences.health_focus,
            "energy_habit": preferences.energy_habit,
            "high_protein_focus": preferences.high_protein_focus,
            "goal_targets": preferences.goal_targets,
            "tier": tier,
        }
        system = (
            "Ты аккуратный нутрициолог H.A.N. Eat. Твоя задача — составить "
            "реалистичную стратегию питания, а не медицинский диагноз. Верни ТОЛЬКО "
            "валидный JSON без markdown и пояснений вне JSON. Не генерируй рецепты, "
            "не перечисляй блюда по дням и не обещай лечебный эффект.\n"
            "Правила качества: учитывай цель, активность, аллергию, диеты, бюджет, "
            "количество людей, время готовки и желаемый темп изменения веса. Если "
            "рост/вес/возраст/пол указаны, ориентируйся на них, но не ставь "
            "экстремальные цели. Если daily_calories уже задан, используй его как "
            "главный лимит и корректируй только если он явно небезопасен. Для похудения "
            "выбирай умеренный дефицит, для набора — умеренный профицит, для здоровья — "
            "поддержание. Белок повышай при muscle_gain/high_protein, но держи БЖУ "
            "реалистичными: сумма процентов должна быть 100.\n"
            "Верни структуру: "
            '{"ai_recommendation":"2-3 коротких практичных предложения на русском",'
            '"daily_calorie_target":число 800-6000,'
            '"macro_split":{"protein_pct":число,"fat_pct":число,"carbs_pct":число},'
            '"meal_calorie_distribution":{"breakfast":0.25,"lunch":0.40,"dinner":0.35},'
            '"meal_timing_notes":"кратко на русском"}. '
            "meal_calorie_distribution должен суммироваться примерно в 1.0."
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
                        "temperature": 0.2,
                        "max_tokens": 420,
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
            data = json.loads(_strip_json_fence(content))
            if not isinstance(data, dict):
                return None
            data = _normalize_strategy(data, preferences)
            data["source"] = "gpt"
            data["duration_days"] = duration_days
            return data
        except Exception as e:
            logger.warning("meal plan GPT failed: %s", e)
            return None


_GOAL_TARGET_LABELS: Dict[str, str] = {
    "lose_3_5kg": "сброс 3–5 кг",
    "lose_5_10kg": "сброс 5–10 кг",
    "lose_10plus": "сброс более 10 кг",
    "stable_appetite": "стабильный аппетит",
    "less_snacking": "меньше перекусов",
    "visible_abs": "рельеф/пресс",
    "gain_2_4kg": "набор 2–4 кг",
    "gain_5plus": "набор 5+ кг",
    "strength": "сила и выносливость",
    "morning_energy": "энергия с утра",
    "no_afternoon_slump": "без спада днём",
    "better_sleep": "лучший сон",
    "kids_variety": "разнообразие для детей",
    "quick_dinners": "быстрые ужины",
    "budget_family": "бюджет на семью",
    "less_sugar": "меньше сахара",
    "more_veggies": "больше овощей",
    "gut_health": "здоровье ЖКТ",
    "maintain_habits": "закрепить привычки",
    "flexible_weekends": "гибкость на выходных",
    "high_protein_meals": "больше белка в приёмах",
    "less_caffeine": "меньше кофеина",
    "one_pot_meals": "блюда в одной кастрюле",
    "hydration": "режим воды",
    "meal_prep": "заготовки на неделю",
}


def _goal_target_labels(ids: List[str]) -> List[str]:
    return [_GOAL_TARGET_LABELS.get(i, i) for i in ids]


def _strip_json_fence(content: str) -> str:
    text = (content or "").strip()
    if text.startswith("```"):
        text = text.removeprefix("```json").removeprefix("```").strip()
        if text.endswith("```"):
            text = text[:-3].strip()
    return text


def _safe_int(value: Any, default: int) -> int:
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return default


def _normalize_strategy(
    data: Dict[str, Any],
    preferences: NutritionPreferences,
) -> Dict[str, Any]:
    fallback_daily = int(preferences.daily_calories or 2000)
    daily = _safe_int(data.get("daily_calorie_target"), fallback_daily)
    data["daily_calorie_target"] = min(6000, max(800, daily))

    raw_macro = data.get("macro_split")
    macro = raw_macro if isinstance(raw_macro, dict) else {}
    protein = max(10, min(45, _safe_int(macro.get("protein_pct"), 30)))
    fat = max(15, min(45, _safe_int(macro.get("fat_pct"), 30)))
    carbs = max(10, min(70, _safe_int(macro.get("carbs_pct"), 100 - protein - fat)))
    total = max(1, protein + fat + carbs)
    data["macro_split"] = {
        "protein_pct": round(protein * 100 / total),
        "fat_pct": round(fat * 100 / total),
        "carbs_pct": max(
            0,
            100 - round(protein * 100 / total) - round(fat * 100 / total),
        ),
    }

    raw_dist = data.get("meal_calorie_distribution")
    dist = raw_dist if isinstance(raw_dist, dict) else {}
    breakfast = _coerce_ratio(dist.get("breakfast"), 0.25)
    lunch = _coerce_ratio(dist.get("lunch"), 0.4)
    dinner = _coerce_ratio(dist.get("dinner"), 0.35)
    total_dist = breakfast + lunch + dinner
    if total_dist <= 0:
        data["meal_calorie_distribution"] = dict(_DEFAULT_MEAL_DISTRIBUTION)
    else:
        data["meal_calorie_distribution"] = {
            "breakfast": round(breakfast / total_dist, 3),
            "lunch": round(lunch / total_dist, 3),
            "dinner": round(dinner / total_dist, 3),
        }

    if not data.get("ai_recommendation"):
        data["ai_recommendation"] = (
            "Сбалансируйте каждый день по белку, овощам и контролю порций. "
            "Корректируйте размер порций по самочувствию и цели."
        )
    if not data.get("meal_timing_notes"):
        data["meal_timing_notes"] = (
            "Держите основные приёмы пищи регулярными, ужин делайте легче обеда."
        )
    return data


def _coerce_ratio(value: Any, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = default
    if parsed > 1:
        parsed = parsed / 100
    return max(0.05, min(0.8, parsed))
