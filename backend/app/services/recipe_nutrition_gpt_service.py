"""Оценка КБЖУ рецепта по названию, ингредиентам и шагам (GPT, без фото)."""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_LANG_NAMES = {
    "ru": "Russian",
    "en": "English",
}


def _parse_num(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = re.sub(
            r"\s*(g|mg|kcal|ккал|г|мг)\s*$",
            "",
            value.strip(),
            flags=re.IGNORECASE,
        )
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def _strip_json_fence(content: str) -> str:
    text = content.strip()
    if text.startswith("```"):
        text = re.sub(r"^```\w*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
    return text.strip()


def analyze_recipe_nutrition_gpt(
    *,
    title: str,
    ingredients: List[str],
    steps: Optional[List[str]] = None,
    description: Optional[str] = None,
    servings: Optional[int] = 1,
    language: str = "ru",
) -> Optional[Dict[str, Any]]:
    """
    Оценка КБЖУ на 1 порцию.
    Возвращает calories, protein_g, carbs_g, fat_g, fiber_g, nutrition, confidence.
    """
    api_key = (settings.OPENAI_API_KEY or "").strip()
    if not api_key or not title.strip():
        return None

    lang_name = _LANG_NAMES.get(language.lower(), "Russian")
    servings_n = max(1, int(servings or 1))
    ing_text = "\n".join(f"- {i}" for i in ingredients if i and i.strip()) or "-"
    steps_text = "\n".join(
        f"{n + 1}. {s}" for n, s in enumerate(steps or []) if s and s.strip()
    ) or "-"

    prompt = (
        f"You are a nutritionist. Reply in {lang_name}. JSON only.\n"
        f"Estimate nutrition PER ONE SERVING (recipe yields {servings_n} servings total).\n"
        f"Title: {title.strip()}\n"
        f"Description: {(description or '').strip() or '-'}\n"
        f"Ingredients:\n{ing_text}\n"
        f"Steps:\n{steps_text}\n"
        "Return realistic estimates for cooked dish per serving:\n"
        '{"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,'
        '"fiber_g":number or null,"confidence":0-1}'
    )

    try:
        with httpx.Client(timeout=25.0) as client:
            resp = client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": (settings.OPENAI_FOOD_SCAN_MODEL or "gpt-4.1-nano").strip(),
                    "max_tokens": 200,
                    "messages": [{"role": "user", "content": prompt}],
                },
            )
        if resp.status_code != 200:
            logger.warning("recipe nutrition GPT HTTP %s", resp.status_code)
            return None

        content = (
            resp.json()
            .get("choices", [{}])[0]
            .get("message", {})
            .get("content")
        )
        if not content:
            return None

        data = json.loads(_strip_json_fence(content))
        if not isinstance(data, dict):
            return None

        calories = _parse_num(data.get("calories"))
        protein = _parse_num(data.get("protein_g") or data.get("protein"))
        carbs = _parse_num(data.get("carbs_g") or data.get("carbohydrates") or data.get("carbs"))
        fat = _parse_num(data.get("fat_g") or data.get("fat"))
        fiber = _parse_num(data.get("fiber_g") or data.get("fiber"))

        nutrition: Dict[str, Any] = {}
        if protein is not None:
            nutrition["protein"] = protein
            nutrition["protein_g"] = protein
        if carbs is not None:
            nutrition["carbohydrates"] = carbs
            nutrition["carbs_g"] = carbs
        if fat is not None:
            nutrition["fat"] = fat
            nutrition["fat_g"] = fat
        if fiber is not None:
            nutrition["fiber"] = fiber
            nutrition["fiber_g"] = fiber
        if calories is not None:
            nutrition["calories"] = int(round(calories))

        return {
            "calories": int(round(calories)) if calories is not None else None,
            "protein_g": protein,
            "carbs_g": carbs,
            "fat_g": fat,
            "fiber_g": fiber,
            "nutrition": nutrition,
            "confidence": _parse_num(data.get("confidence")),
            "source": "gpt",
        }
    except Exception as exc:
        logger.warning("recipe nutrition GPT failed: %s", exc)
        return None
