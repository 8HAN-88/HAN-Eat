"""Оценка КБЖУ по фото через GPT Vision (порция на тарелке, не на 100 г)."""
from __future__ import annotations

import base64
import json
import logging
import re
from typing import Any, Dict, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_LANG_NAMES = {
    "ru": "Russian",
    "en": "English",
    "es": "Spanish",
    "de": "German",
    "fr": "French",
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


def analyze_food_photo_gpt(
    image_bytes: bytes,
    language: str = "ru",
    *,
    priority_fast: bool = False,
) -> Optional[Dict[str, Any]]:
    """
    Возвращает dish_name, portion_grams, calories, confidence, nutrition
    или None при отсутствии ключа / ошибке API.
    """
    api_key = (settings.OPENAI_API_KEY or "").strip()
    if not api_key or not image_bytes:
        return None

    lang_name = _LANG_NAMES.get(language.lower(), "Russian")
    b64 = base64.b64encode(image_bytes).decode("ascii")
    prompt = (
        f"You are a careful food-recognition dietitian. Reply in {lang_name}. "
        "Return JSON only, no markdown.\n"
        "Analyze the visible serving in the photo, not a generic recipe and not per 100g. "
        "First infer the most likely dish, visible ingredients, cooking method, and portion size. "
        "If there are several foods, name the main plate as a combined dish "
        '(for example "chicken with rice and vegetables"). If the photo is unclear, '
        "choose the safest broad dish name and lower confidence.\n"
        "Do not invent hidden ingredients, sauces, oil, sugar, cheese, or drinks unless they are "
        "visible or strongly implied by the dish. Estimate restaurant-style portions realistically: "
        "small snack 80-180g, normal single serving 250-450g, large plate 500-800g. "
        "Calories and macros must be internally consistent with portion_grams and ingredients. "
        "Use kcal for calories, grams for protein/fat/carbohydrates/fiber/sugar, mg for sodium. "
        "Round calories to nearest 10, portion_grams to nearest 5, macros to 0.1g. "
        "Confidence should reflect visual certainty: 0.85+ only when dish and portion are clear; "
        "0.55-0.75 for likely but uncertain; below 0.55 when blurry/partial.\n"
        '{"dish_name":"specific stable dish name","portion_grams":number,'
        '"calories":number,"confidence":0-1,'
        '"nutrition":{"protein":g,"fat":g,"carbohydrates":g,'
        '"fiber":g or null,"sugar":g or null,"sodium":mg or null}}'
    )

    primary = (settings.OPENAI_FOOD_SCAN_MODEL or "gpt-4o-mini").strip()
    models = [primary]
    if not priority_fast and primary != "gpt-4o-mini":
        models.append("gpt-4o-mini")

    timeout = 14.0 if priority_fast else 22.0
    image_detail = "low" if priority_fast else "high"

    try:
        resp = None
        with httpx.Client(timeout=timeout) as client:
            for model in models:
                resp = client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": model,
                        "max_tokens": 220,
                        "temperature": 0,
                        "seed": 42,
                        "messages": [
                            {
                                "role": "user",
                                "content": [
                                    {"type": "text", "text": prompt},
                                    {
                                        "type": "image_url",
                                        "image_url": {
                                            "url": f"data:image/jpeg;base64,{b64}",
                                            "detail": image_detail,
                                        },
                                    },
                                ],
                            }
                        ],
                    },
                )
                if resp.status_code == 200:
                    break
                body_preview = (resp.text or "")[:200]
                if resp.status_code in (400, 404) and "model" in body_preview.lower():
                    logger.warning(
                        "food scan GPT model %s unavailable, trying fallback",
                        model,
                    )
                    continue
                logger.warning("food scan GPT HTTP %s: %s", resp.status_code, body_preview)
                return None
        if resp is None or resp.status_code != 200:
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

        nutrition_raw = data.get("nutrition")
        nutrition: Dict[str, Any] = {}
        if isinstance(nutrition_raw, dict):
            for key, val in nutrition_raw.items():
                if val is None:
                    continue
                parsed = _parse_num(val)
                if parsed is None:
                    continue
                norm = str(key).lower()
                if norm in ("carb", "carbs"):
                    norm = "carbohydrates"
                nutrition[norm] = parsed

        calories = _parse_num(data.get("calories"))
        if calories is not None:
            calories = int(round(calories))

        return {
            "dish_name": (data.get("dish_name") or "").strip() or None,
            "portion_grams": _parse_num(
                data.get("portion_grams") or data.get("portionGrams")
            ),
            "calories": calories,
            "confidence": _parse_num(data.get("confidence")),
            "nutrition": nutrition,
            "source": "gpt",
        }
    except Exception as exc:
        logger.warning("food scan GPT failed: %s", exc)
        return None
