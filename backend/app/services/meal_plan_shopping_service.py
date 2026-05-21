"""Список покупок из плана: объединение ингредиентов и категории."""
from __future__ import annotations

import re
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

from app.schemas.meal_plan import (
    DayPlan,
    ShoppingCategory,
    ShoppingListItem,
    ShoppingListPayload,
)

CATEGORY_RULES: List[Tuple[str, str, List[str]]] = [
    ("vegetables", "Овощи", ["овощ", "салат", "помидор", "огурец", "морков", "лук", "перец", "брокколи", "шпинат", "кабачок", "авокадо", "картоф", "чеснок", "зелень", "ягод"]),
    ("meat", "Мясо", ["куриц", "говядин", "свинин", "индейк", "мяс", "фарш", "бекон", "колбас"]),
    ("fish", "Рыба и морепродукты", ["лосось", "рыб", "тунец", "кревет", "морепродукт"]),
    ("dairy", "Молочные продукты", ["молок", "сыр", "йогурт", "творог", "сливк", "фета", "кефир"]),
    ("grains", "Крупы", ["рис", "греч", "овсян", "киноа", "макарон", "хлеб", "мука", "лапша", "булгур"]),
    ("sauces", "Соусы и масла", ["масло", "соус", "уксус", "мёд", "специ", "приправ", "лимон"]),
]


class MealPlanShoppingService:
    def build_from_days(self, days: List[DayPlan]) -> ShoppingListPayload:
        merged: Dict[str, int] = defaultdict(int)
        for day in days:
            for meal in day.meals:
                for ing in meal.ingredients:
                    key = self._normalize(ing)
                    if key:
                        merged[key] += 1

        by_cat: Dict[str, List[ShoppingListItem]] = defaultdict(list)
        for name, count in sorted(merged.items()):
            cat_id, cat_name = self._categorize(name)
            qty = f"×{count}" if count > 1 else None
            by_cat[cat_id].append(ShoppingListItem(name=name.capitalize(), quantity=qty))

        categories: List[ShoppingCategory] = []
        order = [r[0] for r in CATEGORY_RULES] + ["other"]
        labels = {r[0]: r[1] for r in CATEGORY_RULES}
        labels["other"] = "Другое"
        for cid in order:
            items = by_cat.get(cid)
            if items:
                categories.append(
                    ShoppingCategory(id=cid, name=labels.get(cid, cid), items=items)
                )
        return ShoppingListPayload(categories=categories)

    @staticmethod
    def _normalize(name: str) -> str:
        s = re.sub(r"\s+", " ", name.strip().lower())
        return s

    def _categorize(self, name: str) -> Tuple[str, str]:
        for cat_id, cat_name, keywords in CATEGORY_RULES:
            if any(kw in name for kw in keywords):
                return cat_id, cat_name
        return "other", "Другое"
