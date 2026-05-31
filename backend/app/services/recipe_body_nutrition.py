"""Сборка полей питания в body рецепта."""
from typing import Any, Dict, Optional


def apply_nutrition_to_recipe_body(
    body: Dict[str, Any],
    *,
    calories: Optional[int] = None,
    protein_g: Optional[float] = None,
    carbs_g: Optional[float] = None,
    fat_g: Optional[float] = None,
    fiber_g: Optional[float] = None,
    nutrition: Optional[Dict[str, Any]] = None,
) -> None:
    if calories is not None:
        body["calories"] = calories
    if protein_g is not None:
        body["protein_g"] = protein_g
    if carbs_g is not None:
        body["carbs_g"] = carbs_g
    if fat_g is not None:
        body["fat_g"] = fat_g
    if fiber_g is not None:
        body["fiber_g"] = fiber_g

    merged: Dict[str, Any] = dict(nutrition or {})
    if calories is not None:
        merged["calories"] = calories
    if protein_g is not None:
        merged["protein"] = protein_g
        merged["protein_g"] = protein_g
    if carbs_g is not None:
        merged["carbohydrates"] = carbs_g
        merged["carbs_g"] = carbs_g
    if fat_g is not None:
        merged["fat"] = fat_g
        merged["fat_g"] = fat_g
    if fiber_g is not None:
        merged["fiber"] = fiber_g
        merged["fiber_g"] = fiber_g
    if merged:
        body["nutrition"] = merged
