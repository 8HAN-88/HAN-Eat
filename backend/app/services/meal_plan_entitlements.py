"""Лимиты плана питания по тарифу."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from app.core.entitlements import normalize_tier, tier_includes_ai
from app.models.user import User
from app.services.subscription_service import SubscriptionService


FREE_DURATIONS = [3]
AI_DURATIONS = [3, 7, 14, 21, 30]
FREE_GENERATION_COOLDOWN_DAYS = 7
# Free: без регенерации (TZ). Premium: безлимит.
FREE_MAX_REGENERATIONS = 0

HAN_MEAL_PLAN_COOLDOWN_CODE = "HAN_MEAL_PLAN_COOLDOWN"


class MealPlanEntitlements:
    def __init__(self, user: User, *, subscription_active: bool | None = None):
        self.user = user
        self.tier = normalize_tier(user.subscription_type)
        self._active = subscription_active

    @property
    def is_subscription_active(self) -> bool:
        if self._active is not None:
            return self._active
        return (self.user.subscription_status or "").lower() in (
            "active",
            "trial",
        )

    @property
    def has_ai_access(self) -> bool:
        return tier_includes_ai(self.tier) and self.is_subscription_active

    @property
    def is_pro(self) -> bool:
        return self.tier == "pro" and self.is_subscription_active

    def allowed_durations(self) -> List[int]:
        if self.has_ai_access:
            return list(AI_DURATIONS)
        return list(FREE_DURATIONS)

    def max_duration(self) -> int:
        return max(self.allowed_durations())

    def _utcnow(self) -> datetime:
        return datetime.utcnow()

    def generation_cooldown_active(self) -> bool:
        if self.has_ai_access:
            return False
        ends = self.user.meal_plan_cooldown_ends_at
        if ends is None:
            return False
        return self._utcnow() < ends

    def can_generate_meal_plan(self) -> bool:
        return self.has_ai_access or not self.generation_cooldown_active()

    def validate_generation_allowed(self) -> None:
        if self.can_generate_meal_plan():
            return
        raise PermissionError(
            "Следующий AI meal plan будет доступен позже. "
            "С H.A.N. AI вы можете создавать планы без ожидания."
        )

    def apply_generation_cooldown(self) -> None:
        """После успешной генерации для free — cooldown 7 дней."""
        if self.has_ai_access:
            return
        now = self._utcnow()
        self.user.meal_plan_last_generated_at = now
        self.user.meal_plan_cooldown_ends_at = now + timedelta(
            days=FREE_GENERATION_COOLDOWN_DAYS
        )

    def validate_family_size(self, family_size: int) -> None:
        if family_size > 1 and not self.is_pro:
            raise PermissionError(
                "Семейные планы питания доступны с подпиской H.A.N. Pro"
            )

    def validate_regeneration(self, plan: Dict[str, Any]) -> None:
        if self.has_ai_access:
            return
        raise PermissionError(
            "Обновление блюд и дней доступно с подпиской H.A.N. AI"
        )

    def validate_duration(self, duration_days: int) -> None:
        allowed = self.allowed_durations()
        if duration_days not in allowed:
            if self.has_ai_access:
                raise ValueError(f"duration_days must be one of {allowed}")
            raise PermissionError(
                f"На бесплатном тарифе доступен план на {max(allowed)} дней. "
                "Оформите H.A.N. AI для планов 7–30 дней."
            )

    @staticmethod
    def _iso(dt: Optional[datetime]) -> Optional[str]:
        if dt is None:
            return None
        return dt.replace(microsecond=0).isoformat() + "Z"

    def limits_payload(self) -> Dict[str, Any]:
        ai = self.has_ai_access
        cooldown = self.generation_cooldown_active()
        return {
            "tier": self.tier,
            "allowed_durations": self.allowed_durations(),
            "max_duration": self.max_duration(),
            "ai_meal_plans": ai or self.tier == "free",
            "smart_shopping": ai,
            "unlimited_regeneration": ai,
            "family_meal_plans": self.is_pro,
            "premium_guidance": self.is_pro,
            "max_free_regenerations": 0 if not ai else 999999,
            "can_generate_meal_plan": self.can_generate_meal_plan(),
            "generation_cooldown_active": cooldown,
            "generation_cooldown_days": FREE_GENERATION_COOLDOWN_DAYS,
            "meal_plan_last_generated_at": self._iso(
                self.user.meal_plan_last_generated_at
            ),
            "meal_plan_cooldown_ends_at": self._iso(
                self.user.meal_plan_cooldown_ends_at
            ),
        }

    @classmethod
    def for_user_id(cls, db, user_id: int) -> "MealPlanEntitlements":
        from app.models.user import User as UserModel

        user = db.query(UserModel).filter(UserModel.id == user_id).first()
        if not user:
            raise ValueError("user not found")
        sub = SubscriptionService(db)
        active = sub.has_ai_access(user_id) or (
            normalize_tier(user.subscription_type) == "free"
        )
        return cls(user, subscription_active=active or normalize_tier(user.subscription_type) == "free")
