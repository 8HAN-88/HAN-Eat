"""
Локализация карточек рецептов (перевод на язык из настроек) для подписчиков AI.
Кэш переводов — Redis (см. translate_text в recipes API).
"""
from __future__ import annotations

import concurrent.futures
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

_CYRILLIC = re.compile(r"[\u0400-\u04FF]")


def _cyrillic_ratio(text: str) -> float:
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    return sum(1 for c in letters if _CYRILLIC.match(c)) / len(letters)


def card_needs_localization(card: Dict[str, Any], target_lang: str) -> bool:
    """Нужен ли перевод (в основном Spoonacular EN → RU)."""
    target_lang = (target_lang or "ru").lower()
    title = (card.get("title") or "").strip()
    if not title:
        return False
    source = (card.get("source") or "").strip().lower()
    if source in ("base", "user", "channel"):
        return False
    if target_lang.startswith("ru"):
        return _cyrillic_ratio(title) < 0.2
    if target_lang == "en":
        return _cyrillic_ratio(title) > 0.35
    return True


def viewer_can_localize_recipes(db, user, target_lang: str) -> bool:
    if not user:
        return False
    lang = (target_lang or "").lower()
    if not lang or lang in ("en", "english"):
        return False
    from app.services.subscription_service import SubscriptionService

    return SubscriptionService(db).has_ai_access(user.id)


def _localize_one_card(
    card: Dict[str, Any], target_lang: str, *, full: bool
) -> Dict[str, Any]:
    from app.api.v1.recipes import translate_list, translate_steps, translate_text

    out = dict(card)
    title = out.get("title") or ""
    out["translated_title"] = translate_text(title, target_lang)
    ingredients = out.get("ingredients") or []
    if ingredients:
        capped = ingredients if full else ingredients[:12]
        out["translated_ingredients"] = translate_list(capped, target_lang)
    else:
        out["translated_ingredients"] = []
    if full:
        out["translated_steps"] = translate_steps(out.get("steps") or [], target_lang)
    else:
        out["translated_steps"] = out.get("translated_steps") or out.get("steps") or []
    out["target_language"] = target_lang
    return out


def localize_recipe_cards(
    cards: List[Dict[str, Any]],
    target_lang: str,
    *,
    full: bool = False,
    max_workers: int = 6,
) -> List[Dict[str, Any]]:
    """Параллельный перевод карточек (заголовок + ингредиенты; шаги при full=True)."""
    target_lang = (target_lang or "ru").lower()
    if not cards:
        return cards

    indexed: List[Tuple[int, Dict[str, Any]]] = []
    pending: List[Tuple[int, Dict[str, Any]]] = []

    for idx, card in enumerate(cards):
        if card_needs_localization(card, target_lang):
            pending.append((idx, card))
        else:
            copy = dict(card)
            copy["translated_title"] = copy.get("translated_title") or copy.get("title")
            copy["translated_ingredients"] = (
                copy.get("translated_ingredients") or copy.get("ingredients") or []
            )
            copy["translated_steps"] = copy.get("translated_steps") or copy.get("steps") or []
            copy["target_language"] = target_lang
            indexed.append((idx, copy))

    if pending:

        def _work(item: Tuple[int, Dict[str, Any]]) -> Tuple[int, Dict[str, Any]]:
            i, c = item
            return i, _localize_one_card(c, target_lang, full=full)

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
            for pair in pool.map(_work, pending):
                indexed.append(pair)

    indexed.sort(key=lambda x: x[0])
    return [card for _, card in indexed]


def apply_recipe_localization_to_cards(
    cards: List[Dict[str, Any]],
    target_lang: str,
    db,
    user,
    *,
    full: bool = False,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    lang = (target_lang or "ru").lower()
    meta: Dict[str, Any] = {
        "recipe_translation_language": lang,
        "recipe_translation_enabled": False,
        "recipe_translation_requires_ai": False,
    }
    if not cards:
        return cards, meta

    needs = any(card_needs_localization(c, lang) for c in cards)
    if not needs:
        meta["recipe_translation_enabled"] = True
        return cards, meta

    if not viewer_can_localize_recipes(db, user, lang):
        meta["recipe_translation_requires_ai"] = True
        return cards, meta

    try:
        localized = localize_recipe_cards(cards, lang, full=full)
        meta["recipe_translation_enabled"] = True
        return localized, meta
    except Exception as exc:
        logger.warning("Recipe localization failed: %s", exc)
        return cards, meta
