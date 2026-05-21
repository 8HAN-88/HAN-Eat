"""Опциональный слой рецептов — до 3 карточек, без падения плана."""
from __future__ import annotations

import logging
import random
from typing import Any, Dict, List, Optional, Set

from sqlalchemy.orm import Session

from app.schemas.meal_plan import RecipeCard

logger = logging.getLogger(__name__)


class MealPlanRecipeMatcher:
    MAX_RECIPES = 3

    def __init__(self, db: Optional[Session] = None):
        self.db = db

    def match(
        self,
        *,
        title: str,
        ingredients: List[str],
        target_calories: float,
        diets: List[str],
        allergies: List[str],
        meal_type: str,
        max_ready_time: Optional[int] = None,
        budget_level: Optional[str] = None,
        exclude_recipe_titles: Optional[Set[str]] = None,
        rng: Optional[random.Random] = None,
    ) -> List[RecipeCard]:
        roll = rng or random.Random()
        exclude = {t.lower() for t in (exclude_recipe_titles or set())}
        candidates: List[Dict[str, Any]] = []
        candidates.extend(
            self._from_database(
                title, ingredients, diets=diets, meal_type=meal_type, rng=roll
            )
        )
        spoon_offset = roll.randint(0, 8) if rng else random.randint(0, 8)
        candidates.extend(
            self._from_spoonacular(
                title, max_ready_time, meal_type=meal_type, offset=spoon_offset
            )
        )
        roll.shuffle(candidates)

        scored: List[tuple[float, RecipeCard]] = []
        for c in candidates:
            card = self._to_card(c)
            if not card:
                continue
            if card.title.lower() in exclude:
                continue
            if self._violates_allergies(card, allergies):
                continue
            score = self._score(
                card,
                target_calories,
                title,
                ingredients,
                diets=diets,
                meal_type=meal_type,
                budget_level=budget_level,
            )
            score += roll.uniform(0, 6)
            scored.append((score, card))

        scored.sort(key=lambda x: x[0], reverse=True)
        seen_titles: set[str] = set()
        out: List[RecipeCard] = []
        for _, card in scored:
            key = card.title.lower()
            if key in seen_titles:
                continue
            seen_titles.add(key)
            out.append(card)
            if len(out) >= self.MAX_RECIPES:
                break
        return out

    def _from_database(
        self,
        title: str,
        ingredients: List[str],
        *,
        diets: Optional[List[str]] = None,
        meal_type: Optional[str] = None,
        rng: Optional[random.Random] = None,
    ) -> List[Dict[str, Any]]:
        if not self.db:
            return []
        try:
            from app.models.base_recipe import BaseRecipe

            q = self.db.query(BaseRecipe)
            query = title.split()[0] if title else ""
            if query:
                q = q.filter(BaseRecipe.title.ilike(f"%{query}%"))
            rows = q.order_by(BaseRecipe.popularity_score.desc()).limit(30).all()
            roll = rng or random.Random()
            roll.shuffle(rows)
            out = []
            for r in rows[:18]:
                nut = r.nutrition or {}
                out.append(
                    {
                        "id": r.id,
                        "title": r.title,
                        "image": r.image_url,
                        "calories": r.calories or nut.get("calories") or nut.get("kcal"),
                        "ready_in_minutes": 30,
                    }
                )
            if not out and ingredients:
                ing = ingredients[0]
                rows = list(
                    self.db.query(BaseRecipe)
                    .order_by(BaseRecipe.popularity_score.desc())
                    .limit(20)
                    .all()
                )
                roll.shuffle(rows)
                rows = rows[:12]
                for r in rows:
                    nut = r.nutrition or {}
                    out.append(
                        {
                            "id": r.id,
                            "title": r.title,
                            "image": r.image_url,
                            "calories": nut.get("calories"),
                            "ready_in_minutes": 30,
                        }
                    )
            return out
        except Exception as e:
            logger.debug("meal plan db recipes: %s", e)
            return []

    def _from_spoonacular(
        self,
        title: str,
        max_ready_time: Optional[int],
        *,
        meal_type: Optional[str] = None,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        try:
            from app.api.v1.recipes import SPOONACULAR_API_KEY
            import requests

            if not SPOONACULAR_API_KEY or not title:
                return []
            params = {
                "query": title,
                "number": 6,
                "offset": max(0, offset),
                "addRecipeInformation": "true",
                "apiKey": SPOONACULAR_API_KEY,
            }
            if max_ready_time:
                params["maxReadyTime"] = max_ready_time
            if meal_type == "breakfast":
                params["type"] = "breakfast"
            elif meal_type in ("lunch", "dinner"):
                params["type"] = "main course"
            resp = requests.get(
                "https://api.spoonacular.com/recipes/complexSearch",
                params=params,
                timeout=12,
            )
            if resp.status_code != 200:
                return []
            return resp.json().get("results") or []
        except Exception as e:
            logger.debug("meal plan spoonacular: %s", e)
            return []

    def _to_card(self, raw: Dict[str, Any]) -> Optional[RecipeCard]:
        title = raw.get("title")
        if not title:
            return None
        cal = raw.get("calories")
        if cal is None:
            nut = raw.get("nutrition") or {}
            nutrients = nut.get("nutrients") if isinstance(nut, dict) else None
            if nutrients:
                for n in nutrients:
                    if (n.get("name") or "").lower() == "calories":
                        cal = n.get("amount")
                        break
        rid = raw.get("id")
        return RecipeCard(
            id=int(rid) if rid is not None else None,
            title=str(title),
            image_url=raw.get("image") or raw.get("image_url"),
            calories=int(cal) if cal is not None else None,
            cook_time_min=raw.get("readyInMinutes") or raw.get("ready_in_minutes"),
        )

    def _score(
        self,
        card: RecipeCard,
        target_cal: float,
        title: str,
        ingredients: List[str],
        *,
        diets: Optional[List[str]] = None,
        meal_type: Optional[str] = None,
        budget_level: Optional[str] = None,
    ) -> float:
        score = 0.0
        t_words = set(title.lower().split())
        c_words = set(card.title.lower().split())
        overlap = len(t_words & c_words)
        score += overlap * 10
        if card.calories and target_cal > 0:
            diff = abs(card.calories - target_cal) / target_cal
            score += max(0, 20 - diff * 20)
        for ing in ingredients[:5]:
            if ing.lower() in card.title.lower():
                score += 3
        if diets:
            diet_low = " ".join(d.lower() for d in diets)
            if "веган" in diet_low and any(
                w in card.title.lower() for w in ("куриц", "мяс", "рыб", "яйц")
            ):
                score -= 30
            if "вегетариан" in diet_low and any(
                w in card.title.lower() for w in ("куриц", "мяс", "рыб")
            ):
                score -= 30
        if budget_level == "low" and card.cook_time_min and card.cook_time_min > 45:
            score -= 5
        return score

    @staticmethod
    def _violates_allergies(card: RecipeCard, allergies: List[str]) -> bool:
        low = card.title.lower()
        for a in allergies:
            if a.lower() in low:
                return True
        return False
