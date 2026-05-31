"""Список покупок из плана: объединение ингредиентов и категории."""
from __future__ import annotations

from collections import defaultdict
from typing import Dict, List, Tuple

from app.schemas.meal_plan import (
    DayPlan,
    ShoppingCategory,
    ShoppingListItem,
    ShoppingListPayload,
)
from app.services.ingredient_quantity import merge_ingredient_lines

CATEGORY_RULES: List[Tuple[str, str, List[str]]] = [
    ("vegetables", "Овощи", ["овощ", "салат", "помидор", "огурец", "морков", "лук", "перец", "брокколи", "шпинат", "кабачок", "авокадо", "картоф", "чеснок", "зелень", "ягод"]),
    ("meat", "Мясо", ["куриц", "говядин", "свинин", "индейк", "мяс", "фарш", "бекон", "колбас"]),
    ("fish", "Рыба и морепродукты", ["лосось", "рыб", "тунец", "кревет", "морепродукт"]),
    ("dairy", "Молочные продукты", ["молок", "сыр", "йогурт", "творог", "сливк", "фета", "кефир"]),
    ("grains", "Крупы", ["рис", "греч", "овсян", "киноа", "макарон", "хлеб", "мука", "лапша", "булгур"]),
    ("sauces", "Соусы и масла", ["масло", "соус", "уксус", "мёд", "специ", "приправ", "лимон"]),
]


class MealPlanShoppingService:
    def build_from_days(
        self,
        days: List[DayPlan],
        *,
        family_size: int = 1,
    ) -> ShoppingListPayload:
        lines: List[str] = []
        for day in days:
            for meal in day.meals:
                lines.extend(meal.ingredients)

        merged = merge_ingredient_lines(lines, portions=max(1, family_size))

        by_cat: Dict[str, List[ShoppingListItem]] = defaultdict(list)
        for parsed in merged.values():
            cat_id, _cat_name = self._categorize(parsed.name)
            display_name = parsed.name[:1].upper() + parsed.name[1:] if parsed.name else parsed.name
            qty = parsed.display_quantity() or "по вкусу"
            by_cat[cat_id].append(ShoppingListItem(name=display_name, quantity=qty))

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

    def _categorize(self, name: str) -> Tuple[str, str]:
        low = name.lower()
        for cat_id, cat_name, keywords in CATEGORY_RULES:
            if any(kw in low for kw in keywords):
                return cat_id, cat_name
        return "other", "Другое"
