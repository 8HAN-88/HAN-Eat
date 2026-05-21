"""Структура плана питания на backend (без GPT по дням)."""
from __future__ import annotations

import random
import secrets
import uuid
from datetime import date, timedelta
from typing import Any, Dict, List, Optional, Set

from app.schemas.meal_plan import (
    DayPlan,
    MealBlock,
    MealPlanResponse,
    NutritionPreferences,
)
from app.services.meal_plan_personalization_service import MealPlanPersonalizationService
from app.services.meal_plan_recipe_matcher import MealPlanRecipeMatcher
from app.services.meal_plan_shopping_service import MealPlanShoppingService
from app.services.meal_plan_templates import MEAL_SLOTS, MEAL_TEMPLATES
from app.services.meal_plan_variety import MealVarietyPlanner


class MealPlanBuilderService:
    def __init__(self, db=None):
        self.db = db
        self._personalizer = MealPlanPersonalizationService()
        self._recipe_matcher = MealPlanRecipeMatcher(db)
        self._shopping = MealPlanShoppingService()

    @staticmethod
    def _planner_for(
        preferences: NutritionPreferences,
        duration_days: int,
        *,
        days_raw: Optional[List[Dict[str, Any]]] = None,
        skip_day: Optional[int] = None,
        skip_meal_index: Optional[int] = None,
        variation_seed: Optional[int] = None,
    ) -> MealVarietyPlanner:
        if days_raw is not None:
            return MealVarietyPlanner.from_plan_days(
                days_raw,
                allow_meal_repeats=preferences.allow_meal_repeats,
                meal_repeat_interval_days=preferences.meal_repeat_interval_days,
                skip_day=skip_day,
                skip_meal_index=skip_meal_index,
                variation_seed=variation_seed,
            )
        return MealVarietyPlanner.from_preferences(
            duration_days,
            allow_meal_repeats=preferences.allow_meal_repeats,
            meal_repeat_interval_days=preferences.meal_repeat_interval_days,
            variation_seed=variation_seed,
        )

    @staticmethod
    def _resolve_variation_seed(variation_seed: Optional[int]) -> int:
        if variation_seed is not None:
            return int(variation_seed) & 0x7FFFFFFF
        return secrets.randbelow(2**31)

    @staticmethod
    def _collect_recipe_titles_from_days(days: List[Any]) -> Set[str]:
        titles: Set[str] = set()
        for day in days:
            meals = (
                day.get("meals")
                if isinstance(day, dict)
                else getattr(day, "meals", None)
            )
            if not meals:
                continue
            for meal in meals:
                recipes = (
                    meal.get("recommended_recipes")
                    if isinstance(meal, dict)
                    else getattr(meal, "recommended_recipes", None)
                )
                if not recipes:
                    continue
                for rec in recipes:
                    if isinstance(rec, dict):
                        t = rec.get("title")
                    else:
                        t = getattr(rec, "title", None)
                    if t:
                        titles.add(str(t).lower())
        return titles

    def generate(
        self,
        preferences: NutritionPreferences,
        *,
        duration_days: int,
        tier: str,
        start_date: Optional[date] = None,
        modifier: Optional[str] = None,
        include_recipes: bool = True,
        max_cook_time: Optional[int] = None,
        regeneration_count: int = 0,
        variation_seed: Optional[int] = None,
    ) -> MealPlanResponse:
        seed = self._resolve_variation_seed(variation_seed)
        rng = random.Random(seed)
        strategy = self._personalizer.build_strategy(
            preferences, duration_days=duration_days, tier=tier
        )
        strategy["user_preferences"] = preferences.model_dump()
        daily_target = int(
            strategy.get("daily_calorie_target") or preferences.daily_calories or 2000
        )
        start = start_date or date.today()
        planner = self._planner_for(preferences, duration_days, variation_seed=seed)
        used_recipe_titles: Set[str] = set()
        days: List[DayPlan] = []

        for di in range(duration_days):
            day_date = start + timedelta(days=di)
            meals = self._build_day_meals(
                preferences,
                day_index=di,
                daily_target=daily_target,
                planner=planner,
                modifier=modifier,
                max_cook_time=max_cook_time,
                include_recipes=include_recipes,
                used_recipe_titles=used_recipe_titles,
                rng=rng,
            )
            totals = self._sum_nutrition([m.nutrition for m in meals])
            days.append(
                DayPlan(
                    date=day_date.isoformat(),
                    day_index=di,
                    meals=meals,
                    day_totals=totals,
                )
            )

        family_size = max(1, int(preferences.family_size or 1))
        if family_size > 1:
            days = self._scale_for_family(days, family_size)

        return self._finalize_plan(
            days=days,
            duration_days=duration_days,
            tier=tier,
            strategy=strategy,
            regeneration_count=regeneration_count,
        )

    def regenerate(
        self,
        plan: Dict[str, Any],
        *,
        scope: str,
        day_index: int,
        meal_index: int,
        modifier: Optional[str],
        preferences: NutritionPreferences,
        tier: str,
        variation_seed: Optional[int] = None,
    ) -> MealPlanResponse:
        duration = int(plan.get("duration_days") or len(plan.get("days") or []))
        regen_count = int(plan.get("regeneration_count") or 0) + 1
        seed = self._resolve_variation_seed(variation_seed)
        rng = random.Random(seed)
        max_cook = 25 if modifier == "faster" else None
        budget = "low" if modifier == "cheaper" else preferences.budget_level
        prefs = preferences.model_copy(update={"budget_level": budget})
        strategy = plan.get("nutrition_strategy") or {}
        daily_target = int(
            strategy.get("daily_calorie_target") or prefs.daily_calories or 2000
        )

        if scope == "plan" or modifier == "refresh":
            fresh = self.generate(
                prefs,
                duration_days=duration,
                tier=tier,
                modifier=modifier,
                max_cook_time=max_cook,
                regeneration_count=regen_count,
                variation_seed=seed,
            )
            return fresh.model_copy(
                update={
                    "plan_id": plan.get("plan_id") or fresh.plan_id,
                    "ai_recommendation": (
                        fresh.ai_recommendation
                        if modifier == "refresh"
                        else plan.get("ai_recommendation") or fresh.ai_recommendation
                    ),
                    "nutrition_strategy": plan.get("nutrition_strategy")
                    or fresh.nutrition_strategy,
                }
            )

        old_days_raw = plan.get("days") or []
        old_days = [
            DayPlan.model_validate(d) if isinstance(d, dict) else d
            for d in old_days_raw
        ]

        used_recipe_titles = self._collect_recipe_titles_from_days(old_days_raw)

        if scope == "day" and 0 <= day_index < len(old_days):
            planner = self._planner_for(
                prefs,
                duration,
                days_raw=old_days_raw,
                skip_day=day_index,
                variation_seed=seed,
            )
            new_meals = self._build_day_meals(
                prefs,
                day_index=day_index,
                daily_target=daily_target,
                planner=planner,
                modifier=modifier,
                max_cook_time=max_cook,
                include_recipes=True,
                used_recipe_titles=used_recipe_titles,
                rng=rng,
            )
            new_days = list(old_days)
            new_days[day_index] = old_days[day_index].model_copy(
                update={
                    "meals": new_meals,
                    "day_totals": self._sum_nutrition([m.nutrition for m in new_meals]),
                }
            )
        elif scope == "meal" and 0 <= day_index < len(old_days):
            planner = self._planner_for(
                prefs,
                duration,
                days_raw=old_days_raw,
                skip_day=day_index,
                skip_meal_index=meal_index,
                variation_seed=seed,
            )
            exclude = planner.collect_titles_from_plan(
                old_days_raw, except_day=day_index, except_meal=meal_index
            )
            old_meals = old_days[day_index].meals
            if 0 <= meal_index < len(old_meals):
                exclude.add(old_meals[meal_index].title)
            meal_type = MEAL_SLOTS[meal_index] if meal_index < len(MEAL_SLOTS) else "lunch"
            new_meal = self._build_single_meal(
                prefs,
                meal_type=meal_type,
                day_index=day_index,
                meal_index=meal_index,
                daily_target=daily_target,
                planner=planner,
                modifier=modifier,
                max_cook_time=max_cook,
                exclude_titles=exclude,
                used_recipe_titles=used_recipe_titles,
                rng=rng,
            )
            merged = list(old_days[day_index].meals)
            if 0 <= meal_index < len(merged):
                merged[meal_index] = new_meal
            new_days = list(old_days)
            new_days[day_index] = old_days[day_index].model_copy(
                update={
                    "meals": merged,
                    "day_totals": self._sum_nutrition([m.nutrition for m in merged]),
                }
            )
        else:
            return self.generate(
                prefs,
                duration_days=duration,
                tier=tier,
                modifier=modifier,
                max_cook_time=max_cook,
                regeneration_count=regen_count,
                variation_seed=seed,
            )

        family_size = max(1, int(prefs.family_size or 1))
        if family_size > 1:
            new_days = self._scale_for_family(new_days, family_size)

        return self._finalize_plan(
            days=new_days,
            duration_days=duration,
            tier=tier,
            strategy=strategy,
            plan_id=plan.get("plan_id"),
            ai_recommendation=plan.get("ai_recommendation", ""),
            regeneration_count=regen_count,
        )

    def _finalize_plan(
        self,
        *,
        days: List[DayPlan],
        duration_days: int,
        tier: str,
        strategy: Dict[str, Any],
        plan_id: Optional[str] = None,
        ai_recommendation: Optional[str] = None,
        regeneration_count: int = 0,
    ) -> MealPlanResponse:
        shopping = self._shopping.build_from_days(days)
        ent_ai = tier in ("ai", "pro")
        rec = ai_recommendation if ai_recommendation is not None else strategy.get(
            "ai_recommendation", ""
        )
        return MealPlanResponse(
            plan_id=plan_id or str(uuid.uuid4()),
            duration_days=duration_days,
            tier=tier,
            ai_recommendation=rec,
            nutrition_strategy=strategy,
            days=days,
            shopping_list=shopping,
            can_regenerate_unlimited=ent_ai,
            smart_shopping=ent_ai,
            regeneration_count=regeneration_count,
        )

    def _build_day_meals(
        self,
        preferences: NutritionPreferences,
        *,
        day_index: int,
        daily_target: int,
        planner: MealVarietyPlanner,
        modifier: Optional[str],
        max_cook_time: Optional[int],
        include_recipes: bool,
        exclude_titles: Optional[Set[str]] = None,
        used_recipe_titles: Optional[Set[str]] = None,
        rng: Optional[random.Random] = None,
    ) -> List[MealBlock]:
        per_meal = daily_target // len(MEAL_SLOTS)
        blocks: List[MealBlock] = []
        recipe_used = used_recipe_titles if used_recipe_titles is not None else set()
        for slot_i, meal_type in enumerate(MEAL_SLOTS):
            blocks.append(
                self._build_single_meal(
                    preferences,
                    meal_type=meal_type,
                    day_index=day_index,
                    meal_index=slot_i,
                    daily_target=per_meal,
                    planner=planner,
                    modifier=modifier,
                    max_cook_time=max_cook_time,
                    include_recipes=include_recipes,
                    exclude_titles=exclude_titles,
                    used_recipe_titles=recipe_used,
                    rng=rng,
                )
            )
        return blocks

    def _build_single_meal(
        self,
        preferences: NutritionPreferences,
        *,
        meal_type: str,
        day_index: int,
        meal_index: int,
        daily_target: int,
        planner: MealVarietyPlanner,
        modifier: Optional[str],
        max_cook_time: Optional[int],
        include_recipes: bool = True,
        exclude_titles: Optional[Set[str]] = None,
        used_recipe_titles: Optional[Set[str]] = None,
        rng: Optional[random.Random] = None,
    ) -> MealBlock:
        pool = self._filtered_pool(meal_type, preferences, modifier=modifier)
        tpl = planner.pick(
            pool,
            meal_type=meal_type,
            day_index=day_index,
            slot_index=meal_index,
            exclude_titles=exclude_titles,
        )
        scale = daily_target / max(tpl["cal"], 1)
        nutrition = {
            "calories": round(tpl["cal"] * scale),
            "protein_g": round(tpl["p"] * scale, 1),
            "fat_g": round(tpl["f"] * scale, 1),
            "carbs_g": round(tpl["c"] * scale, 1),
        }
        ingredients = self._filter_allergens(tpl["ingredients"], preferences.allergies)
        recipes = []
        if include_recipes:
            recipes = self._recipe_matcher.match(
                title=tpl["title"],
                ingredients=ingredients,
                target_calories=nutrition["calories"],
                diets=preferences.diets,
                allergies=preferences.allergies,
                meal_type=meal_type,
                max_ready_time=max_cook_time,
                budget_level=preferences.budget_level,
                exclude_recipe_titles=used_recipe_titles,
                rng=rng,
            )
            if used_recipe_titles is not None:
                for rec in recipes:
                    used_recipe_titles.add(rec.title.lower())
        return MealBlock(
            meal_type=meal_type,  # type: ignore[arg-type]
            title=tpl["title"],
            guidance=tpl["guidance"],
            ingredients=ingredients,
            nutrition=nutrition,
            recommended_recipes=recipes,
        )

    def _filtered_pool(
        self,
        meal_type: str,
        preferences: NutritionPreferences,
        *,
        modifier: Optional[str],
    ) -> List[Dict[str, Any]]:
        pool = list(MEAL_TEMPLATES.get(meal_type, MEAL_TEMPLATES["lunch"]))
        diets = {d.lower() for d in preferences.diets}

        if any("веган" in d for d in diets):
            pool = [
                t
                for t in pool
                if "яйц" not in t["title"].lower()
                and "творог" not in t["title"].lower()
                and "лосось" not in t["title"].lower()
                and "кревет" not in t["title"].lower()
                and "тунец" not in t["title"].lower()
                and "говядин" not in t["title"].lower()
                and "куриц" not in t["title"].lower()
                and "индейк" not in t["title"].lower()
            ]
        if any("вегетариан" in d for d in diets):
            pool = [
                t
                for t in pool
                if "курин" not in t["title"].lower()
                and "индейк" not in t["title"].lower()
                and "лосось" not in t["title"].lower()
                and "тунец" not in t["title"].lower()
                and "кревет" not in t["title"].lower()
                and "говядин" not in t["title"].lower()
                and "рыб" not in t["title"].lower()
            ]

        prefs_low = preferences.meal_preferences or []
        pref_text = " ".join(prefs_low).lower()
        if modifier == "faster" or "быстр" in pref_text:
            quick = [t for t in pool if t.get("quick")]
            if quick:
                pool = quick
        if (
            modifier == "cheaper"
            or preferences.budget_level == "low"
            or "бюджет" in pref_text
        ):
            cheap = [t for t in pool if t.get("budget_low")]
            if cheap:
                pool = cheap

        if not pool:
            pool = list(MEAL_TEMPLATES.get(meal_type, MEAL_TEMPLATES["lunch"]))
        return pool

    def _filter_allergens(self, ingredients: List[str], allergies: List[str]) -> List[str]:
        if not allergies:
            return ingredients
        blocked = {a.lower() for a in allergies}
        result = []
        for ing in ingredients:
            low = ing.lower()
            if any(b in low or low in b for b in blocked):
                continue
            result.append(ing)
        return result or ingredients

    def _scale_for_family(self, days: List[DayPlan], family_size: int) -> List[DayPlan]:
        scaled: List[DayPlan] = []
        for day in days:
            meals: List[MealBlock] = []
            for meal in day.meals:
                nut = {
                    k: round(v * family_size, 1)
                    if k != "calories"
                    else round(v * family_size)
                    for k, v in meal.nutrition.items()
                }
                guidance = meal.guidance
                if family_size > 1 and "человек" not in guidance.lower():
                    guidance = f"{guidance} (расчёт на {family_size} чел.)"
                meals.append(
                    meal.model_copy(
                        update={
                            "nutrition": nut,
                            "guidance": guidance,
                        }
                    )
                )
            totals = self._sum_nutrition([m.nutrition for m in meals])
            scaled.append(day.model_copy(update={"meals": meals, "day_totals": totals}))
        return scaled

    @staticmethod
    def _sum_nutrition(items: List[Dict[str, float]]) -> Dict[str, float]:
        totals = {"calories": 0.0, "protein_g": 0.0, "fat_g": 0.0, "carbs_g": 0.0}
        for n in items:
            totals["calories"] += float(n.get("calories") or 0)
            totals["protein_g"] += float(n.get("protein_g") or 0)
            totals["fat_g"] += float(n.get("fat_g") or 0)
            totals["carbs_g"] += float(n.get("carbs_g") or 0)
        return {k: round(v, 1) for k, v in totals.items()}
