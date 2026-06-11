"""Тесты meal plan builder, shopping, entitlements."""
from datetime import date, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.api.v1.meal_plans import _validate_regeneration_target
from app.schemas.meal_plan import NutritionPreferences, RegenerateMealPlanRequest
from app.services.meal_plan_builder_service import MealPlanBuilderService
from app.services.meal_plan_entitlements import MealPlanEntitlements
from app.services.ingredient_quantity import merge_ingredient_lines, parse_ingredient_line
from app.services.meal_plan_shopping_service import MealPlanShoppingService


class _User:
    subscription_type = "free"
    subscription_status = "active"


class _AiUser:
    subscription_type = "ai"
    subscription_status = "active"


def test_free_tier_only_3_days():
    ent = MealPlanEntitlements(_User(), subscription_active=True)
    assert ent.allowed_durations() == [3]
    with pytest.raises(PermissionError):
        ent.validate_duration(7)


def test_ai_tier_all_durations():
    ent = MealPlanEntitlements(_AiUser(), subscription_active=True)
    assert 30 in ent.allowed_durations()
    ent.validate_duration(14)


def test_generate_plan_has_meals_and_recommendation():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(daily_calories=2000, diets=["Кето"]),
        duration_days=3,
        tier="free",
        start_date=date(2026, 5, 16),
        include_recipes=False,
    )
    assert plan.duration_days == 3
    assert len(plan.days) == 3
    assert plan.ai_recommendation
    assert plan.days[0].meals
    assert plan.days[0].day_totals["calories"] > 0


def test_shopping_list_categories():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=1,
        tier="free",
        include_recipes=False,
    )
    cats = plan.shopping_list.categories
    assert cats
    names = {c.name for c in cats}
    assert "Овощи" in names or "Другое" in names


def test_regenerate_meal_preserves_recommendation():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=2,
        tier="ai",
        include_recipes=False,
    )
    original = plan.model_dump(mode="json")
    original["ai_recommendation"] = "Сохранённая рекомендация"
    regen = builder.regenerate(
        original,
        scope="meal",
        day_index=0,
        meal_index=0,
        modifier="replace",
        preferences=NutritionPreferences(),
        tier="ai",
    )
    assert regen.ai_recommendation == "Сохранённая рекомендация"
    assert regen.plan_id == original["plan_id"]


def test_plan_avoids_same_meal_on_consecutive_days():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=7,
        tier="ai",
        include_recipes=False,
    )
    for slot in range(3):
        for di in range(1, len(plan.days)):
            prev = plan.days[di - 1].meals[slot].title
            curr = plan.days[di].meals[slot].title
            assert prev != curr, f"slot {slot} day {di}: repeated {prev}"


def test_regenerate_meal_preserves_other_days():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=3,
        tier="ai",
        include_recipes=False,
    )
    original = plan.model_dump(mode="json")
    day1_title_before = original["days"][1]["meals"][0]["title"]
    regen = builder.regenerate(
        original,
        scope="meal",
        day_index=0,
        meal_index=0,
        modifier="replace",
        preferences=NutritionPreferences(),
        tier="ai",
    )
    assert regen.days[1].meals[0].title == day1_title_before


def test_no_repeats_when_user_disallows():
    builder = MealPlanBuilderService(db=None)
    prefs = NutritionPreferences(allow_meal_repeats=False, meal_repeat_interval_days=7)
    plan = builder.generate(
        prefs,
        duration_days=3,
        tier="ai",
        include_recipes=False,
    )
    titles = [m.title for d in plan.days for m in d.meals]
    assert len(titles) == len(set(titles))


def test_repeats_allowed_after_interval():
    builder = MealPlanBuilderService(db=None)
    prefs = NutritionPreferences(allow_meal_repeats=True, meal_repeat_interval_days=2)
    plan = builder.generate(
        prefs,
        duration_days=5,
        tier="ai",
        include_recipes=False,
    )
    by_slot: dict = {0: [], 1: [], 2: []}
    for day in plan.days:
        for i, meal in enumerate(day.meals):
            by_slot[i].append(meal.title)
    # При интервале 2 одно блюдо может встретиться снова не раньше чем через 2 дня
    for slot_titles in by_slot.values():
        for i in range(len(slot_titles)):
            for j in range(i + 1, len(slot_titles)):
                if slot_titles[i] == slot_titles[j]:
                    assert j - i >= 2


def test_free_regeneration_blocked():
    ent = MealPlanEntitlements(_User(), subscription_active=True)
    with pytest.raises(PermissionError):
        ent.validate_regeneration({"regeneration_count": 0})


def test_free_generation_cooldown():
    user = _User()
    user.meal_plan_cooldown_ends_at = datetime.utcnow() + timedelta(days=3)
    ent = MealPlanEntitlements(user, subscription_active=True)
    assert ent.generation_cooldown_active()
    assert not ent.can_generate_meal_plan()
    with pytest.raises(PermissionError):
        ent.validate_generation_allowed()


def test_free_apply_cooldown_after_generate():
    user = _User()
    ent = MealPlanEntitlements(user, subscription_active=True)
    ent.apply_generation_cooldown()
    assert user.meal_plan_last_generated_at is not None
    assert user.meal_plan_cooldown_ends_at is not None
    assert not ent.can_generate_meal_plan()


def test_ai_no_generation_cooldown():
    user = _AiUser()
    user.meal_plan_cooldown_ends_at = datetime.utcnow() + timedelta(days=5)
    ent = MealPlanEntitlements(user, subscription_active=True)
    assert ent.can_generate_meal_plan()


def test_generate_differs_with_different_seeds():
    builder = MealPlanBuilderService(db=None)
    prefs = NutritionPreferences()
    a = builder.generate(prefs, duration_days=3, tier="ai", include_recipes=False, variation_seed=1)
    b = builder.generate(prefs, duration_days=3, tier="ai", include_recipes=False, variation_seed=999)
    titles_a = [m.title for d in a.days for m in d.meals]
    titles_b = [m.title for d in b.days for m in d.meals]
    assert titles_a != titles_b


def test_regenerate_meal_changes_title():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=2,
        tier="ai",
        include_recipes=False,
        variation_seed=10,
    )
    original = plan.model_dump(mode="json")
    before = original["days"][0]["meals"][0]["title"]
    regen = builder.regenerate(
        original,
        scope="meal",
        day_index=0,
        meal_index=0,
        modifier="replace",
        preferences=NutritionPreferences(),
        tier="ai",
        variation_seed=42,
    )
    after = regen.days[0].meals[0].title
    assert after != before


def test_validate_regeneration_rejects_empty_plan():
    body = RegenerateMealPlanRequest(plan={"days": []}, scope="meal")
    with pytest.raises(HTTPException) as exc:
        _validate_regeneration_target(body)
    assert exc.value.status_code == 400


def test_validate_regeneration_rejects_bad_meal_index():
    body = RegenerateMealPlanRequest(
        plan={"days": [{"meals": [{"title": "Завтрак"}]}]},
        scope="meal",
        meal_index=3,
    )
    with pytest.raises(HTTPException) as exc:
        _validate_regeneration_target(body)
    assert exc.value.status_code == 400


def test_regenerate_faster_changes_templates():
    builder = MealPlanBuilderService(db=None)
    plan = builder.generate(
        NutritionPreferences(),
        duration_days=1,
        tier="ai",
        include_recipes=False,
    )
    regen = builder.regenerate(
        plan.model_dump(mode="json"),
        scope="meal",
        day_index=0,
        meal_index=0,
        modifier="faster",
        preferences=NutritionPreferences(),
        tier="ai",
    )
    assert regen.days[0].meals


def test_parse_ingredient_grams():
    p = parse_ingredient_line("куриная грудка 200 г")
    assert "грудка" in p.name.lower()
    assert p.amount == 200
    assert p.unit == "g"


def test_merge_ingredient_quantities():
    merged = merge_ingredient_lines(
        ["куриная грудка 200 г", "куриная грудка 300 г"],
        portions=1,
    )
    assert len(merged) == 1
    val = next(iter(merged.values()))
    assert val.amount == 500


def test_shopping_service_quantities():
    svc = MealPlanShoppingService()
    from app.schemas.meal_plan import DayPlan, MealBlock

    day = DayPlan(
        date="2026-05-16",
        day_index=0,
        meals=[
            MealBlock(
                meal_type="lunch",
                title="Обед",
                guidance="",
                ingredients=["куриная грудка 200 г", "брокколи 150 г"],
                nutrition={"calories": 400, "protein_g": 30, "fat_g": 10, "carbs_g": 20},
            ),
        ],
        day_totals={"calories": 400, "protein_g": 30, "fat_g": 10, "carbs_g": 20},
    )
    payload = svc.build_from_days([day], family_size=2)
    items = [i for c in payload.categories for i in c.items]
    chicken = next(i for i in items if "грудка" in i.name.lower())
    assert "400" in (chicken.quantity or "")
