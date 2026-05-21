"""
AI Meal Plan: генерация, регенерация, лимиты по тарифу.
GPT — только персонализация (1 вызов). Структура и shopping — backend.
"""
from datetime import date
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.core.entitlements import HAN_AI_REQUIRED_CODE
from app.models.user import User
from app.schemas.meal_plan import (
    GenerateMealPlanRequest,
    MealPlanLimitsResponse,
    MealPlanResponse,
    RegenerateMealPlanRequest,
)
from app.services.analytics_service import AnalyticsService
from app.services.meal_plan_builder_service import MealPlanBuilderService
from app.services.meal_plan_entitlements import (
    HAN_MEAL_PLAN_COOLDOWN_CODE,
    MealPlanEntitlements,
)
from app.services.meal_plan_storage_service import MealPlanStorageService

router = APIRouter()


class SaveMealPlanRequest(BaseModel):
    plan: Dict[str, Any]
    family_size: int = Field(1, ge=1, le=8)


class ApplyCalendarRequest(BaseModel):
    meals_added: int = Field(0, ge=0)
    duration_days: int = Field(0, ge=0)


def _entitlements(user: User, db: Session) -> MealPlanEntitlements:
    from app.services.subscription_service import SubscriptionService

    sub = SubscriptionService(db)
    active_ai = sub.has_ai_access(user.id)
    return MealPlanEntitlements(
        user,
        subscription_active=active_ai or user.subscription_type == "free",
    )


def _persist_plan(
    db: Session,
    user_id: int,
    plan: MealPlanResponse,
    family_size: int,
) -> None:
    storage = MealPlanStorageService(db)
    storage.save_plan(
        user_id,
        plan.model_dump(mode="json"),
        family_size=family_size,
    )


@router.get("/limits", response_model=MealPlanLimitsResponse)
async def meal_plan_limits(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    ent = _entitlements(current_user, db)
    return MealPlanLimitsResponse(**ent.limits_payload())


@router.post("/generate", response_model=MealPlanResponse)
async def generate_meal_plan(
    body: GenerateMealPlanRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    ent = _entitlements(current_user, db)
    try:
        ent.validate_generation_allowed()
    except PermissionError as e:
        AnalyticsService(db).log_event(
            event_type="meal_plan_cooldown_blocked",
            entity_type="user",
            entity_id=current_user.id,
            user_id=current_user.id,
            metadata={"tier": ent.tier},
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_MEAL_PLAN_COOLDOWN_CODE,
                "message": str(e),
            },
        ) from e
    try:
        ent.validate_duration(body.duration_days)
    except PermissionError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": str(e),
            },
        ) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    try:
        ent.validate_family_size(body.preferences.family_size)
    except PermissionError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "HAN_PRO_REQUIRED", "message": str(e)},
        ) from e

    if body.duration_days > 3 and not ent.has_ai_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": "Планы на 7–30 дней доступны с подпиской H.A.N. AI",
            },
        )

    start = None
    if body.start_date:
        try:
            start = date.fromisoformat(body.start_date[:10])
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid start_date")

    builder = MealPlanBuilderService(db)
    plan = builder.generate(
        body.preferences,
        duration_days=body.duration_days,
        tier=ent.tier,
        start_date=start,
        variation_seed=body.variation_seed,
    )

    analytics = AnalyticsService(db)
    analytics.log_event(
        event_type="meal_plan_generated",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
        metadata={
            "duration_days": body.duration_days,
            "tier": ent.tier,
            "has_recipes": any(
                m.recommended_recipes for d in plan.days for m in d.meals
            ),
            "family_size": body.preferences.family_size,
        },
    )
    _persist_plan(db, current_user.id, plan, body.preferences.family_size)
    ent.apply_generation_cooldown()
    db.add(current_user)
    db.commit()
    return plan


@router.post("/regenerate", response_model=MealPlanResponse)
async def regenerate_meal_plan(
    body: RegenerateMealPlanRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    ent = _entitlements(current_user, db)
    try:
        ent.validate_regeneration(body.plan)
    except PermissionError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": HAN_AI_REQUIRED_CODE, "message": str(e)},
        ) from e
    if body.scope == "plan" and not ent.has_ai_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": "Полная замена плана доступна с H.A.N. AI",
            },
        )
    if body.modifier in ("faster", "cheaper") and not ent.has_ai_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": "Умная замена блюд доступна с H.A.N. AI",
            },
        )

    from app.schemas.meal_plan import NutritionPreferences

    prefs = body.preferences
    strategy = body.plan.get("nutrition_strategy") or {}
    stored = strategy.get("user_preferences")
    stored_dict = dict(stored) if isinstance(stored, dict) else {}
    if prefs is None:
        base: Dict[str, Any] = {
            "daily_calories": strategy.get("daily_calorie_target"),
        }
        base.update(stored_dict)
        prefs = NutritionPreferences.model_validate(base)
    elif stored_dict:
        merged = {**stored_dict, **prefs.model_dump()}
        prefs = NutritionPreferences.model_validate(merged)

    try:
        ent.validate_family_size(prefs.family_size)
    except PermissionError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "HAN_PRO_REQUIRED", "message": str(e)},
        ) from e

    builder = MealPlanBuilderService(db)
    plan = builder.regenerate(
        body.plan,
        scope=body.scope,
        day_index=body.day_index,
        meal_index=body.meal_index,
        modifier=body.modifier,
        preferences=prefs,
        tier=ent.tier,
        variation_seed=body.variation_seed,
    )

    analytics = AnalyticsService(db)
    analytics.log_event(
        event_type="meal_plan_regenerated",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
        metadata={
            "scope": body.scope,
            "modifier": body.modifier,
            "tier": ent.tier,
        },
    )
    family_size = int((prefs.family_size if prefs else 1) or 1)
    _persist_plan(db, current_user.id, plan, family_size)
    db.commit()
    return plan


@router.get("/saved/latest")
async def get_latest_saved_plan(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        data = MealPlanStorageService(db).get_latest(current_user.id)
    except Exception:
        data = None
    if not data:
        raise HTTPException(status_code=404, detail="No saved plan")
    return data


@router.get("/saved/{plan_id}")
async def get_saved_plan_by_id(
    plan_id: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    data = MealPlanStorageService(db).get_by_plan_id(current_user.id, plan_id)
    if not data:
        raise HTTPException(status_code=404, detail="Plan not found")
    return data


@router.get("/saved")
async def list_saved_plans(
    limit: int = Query(10, ge=1, le=30),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return {"plans": MealPlanStorageService(db).list_plans(current_user.id, limit=limit)}


@router.post("/save")
async def save_meal_plan(
    body: SaveMealPlanRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    ent = _entitlements(current_user, db)
    try:
        ent.validate_family_size(body.family_size)
    except PermissionError as e:
        raise HTTPException(
            status_code=403,
            detail={"code": "HAN_PRO_REQUIRED", "message": str(e)},
        ) from e
    row = MealPlanStorageService(db).save_plan(
        current_user.id, body.plan, family_size=body.family_size
    )
    db.commit()
    return {"ok": True, "id": row.id, "plan_id": row.plan_id}


@router.get("/analytics")
async def meal_plan_analytics(
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return AnalyticsService(db).get_meal_plan_analytics(current_user.id, days=days)


@router.post("/apply-calendar", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
async def log_apply_calendar(
    body: ApplyCalendarRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    AnalyticsService(db).log_event(
        event_type="meal_plan_applied_to_calendar",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
        metadata={
            "meals_added": body.meals_added,
            "duration_days": body.duration_days,
        },
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/shopping-list/apply", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
async def log_shopping_list_apply(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Клиент применил shopping list локально — только аналитика."""
    AnalyticsService(db).log_event(
        event_type="meal_plan_shopping_applied",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
