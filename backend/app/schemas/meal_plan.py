"""Схемы AI meal plan API."""
from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

MealTypeStr = Literal["breakfast", "lunch", "dinner", "snack"]
RegenerateScope = Literal["meal", "day", "plan"]
RegenerateModifier = Literal["faster", "cheaper", "replace", "refresh"]
BudgetLevel = Literal["low", "medium", "high"]


class NutritionPreferences(BaseModel):
    model_config = ConfigDict(extra="ignore")

    daily_calories: Optional[int] = Field(None, ge=800, le=6000)
    diets: List[str] = Field(default_factory=list)
    allergies: List[str] = Field(default_factory=list)
    diet_type: Optional[str] = None
    budget_level: BudgetLevel = "medium"
    meal_preferences: List[str] = Field(default_factory=list)
    family_size: int = Field(1, ge=1, le=8)
    allow_meal_repeats: bool = True
    meal_repeat_interval_days: int = Field(4, ge=1, le=21)
    primary_goal: Optional[str] = None
    activity_level: Optional[str] = None
    sex: Optional[str] = None
    age: Optional[int] = Field(None, ge=10, le=120)
    height_cm: Optional[int] = Field(None, ge=100, le=250)
    weight_kg: Optional[int] = Field(None, ge=30, le=300)
    meals_per_day: Optional[int] = Field(None, ge=2, le=6)
    cooking_time: Optional[str] = None
    cooking_skill: Optional[str] = None
    weight_pace: Optional[str] = None
    health_focus: Optional[str] = None
    energy_habit: Optional[str] = None
    high_protein_focus: bool = False
    goal_targets: List[str] = Field(default_factory=list)


class GenerateMealPlanRequest(BaseModel):
    duration_days: int = Field(3, ge=1, le=30)
    preferences: NutritionPreferences = Field(default_factory=NutritionPreferences)
    start_date: Optional[str] = None  # ISO date
    variation_seed: Optional[int] = Field(
        None,
        description="Сид для разнообразия блюд/рецептов (мс с клиента)",
    )


class RegenerateMealPlanRequest(BaseModel):
    plan: Dict[str, Any]
    scope: RegenerateScope = "meal"
    day_index: int = Field(0, ge=0)
    meal_index: int = Field(0, ge=0)
    modifier: Optional[RegenerateModifier] = None
    preferences: Optional[NutritionPreferences] = None
    variation_seed: Optional[int] = Field(
        None,
        description="Новый сид при замене блюда/дня/плана",
    )


class RecipeCard(BaseModel):
    id: Optional[int] = None
    title: str
    image_url: Optional[str] = None
    calories: Optional[int] = None
    cook_time_min: Optional[int] = None


class MealBlock(BaseModel):
    meal_type: MealTypeStr
    title: str
    guidance: str
    ingredients: List[str]
    nutrition: Dict[str, float]
    recommended_recipes: List[RecipeCard] = Field(default_factory=list)


class DayPlan(BaseModel):
    date: str
    day_index: int
    meals: List[MealBlock]
    day_totals: Dict[str, float]


class ShoppingListItem(BaseModel):
    name: str
    quantity: Optional[str] = None


class ShoppingCategory(BaseModel):
    id: str
    name: str
    items: List[ShoppingListItem]


class ShoppingListPayload(BaseModel):
    categories: List[ShoppingCategory]


class MealPlanResponse(BaseModel):
    plan_id: str
    duration_days: int
    tier: str
    ai_recommendation: str
    nutrition_strategy: Dict[str, Any]
    days: List[DayPlan]
    shopping_list: ShoppingListPayload
    can_regenerate_unlimited: bool = False
    smart_shopping: bool = False
    regeneration_count: int = 0


class MealPlanLimitsResponse(BaseModel):
    tier: str
    allowed_durations: List[int]
    max_duration: int
    ai_meal_plans: bool
    smart_shopping: bool
    unlimited_regeneration: bool
    family_meal_plans: bool
    premium_guidance: bool
    max_free_regenerations: int = 0
    can_generate_meal_plan: bool = True
    generation_cooldown_active: bool = False
    generation_cooldown_days: int = 7
    meal_plan_last_generated_at: Optional[str] = None
    meal_plan_cooldown_ends_at: Optional[str] = None
