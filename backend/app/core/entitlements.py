"""
Привилегии по тарифам: free | ai | creator | pro.
"""
from typing import Any, Dict, Literal, Optional

SubscriptionTier = Literal["free", "ai", "creator", "pro"]
SubscriptionStatus = Literal["active", "expired", "canceled", "trial"]

HAN_PLUS_REQUIRED_CODE = "HAN_PLUS_REQUIRED"
HAN_AI_REQUIRED_CODE = "HAN_AI_REQUIRED"
HAN_CREATOR_REQUIRED_CODE = "HAN_CREATOR_REQUIRED"
HAN_PRO_REQUIRED_CODE = "HAN_PRO_REQUIRED"
LOGIN_REQUIRED_CODE = "LOGIN_REQUIRED"
AI_SCANS_EXHAUSTED_CODE = "AI_SCANS_EXHAUSTED"
AI_SCAN_RESERVE_REQUIRED_CODE = "AI_SCAN_RESERVE_REQUIRED"

VALID_PRODUCTS = frozenset({"ai", "creator", "pro"})


def normalize_tier(subscription_type: Optional[str]) -> SubscriptionTier:
    if not subscription_type:
        return "free"
    t = subscription_type.strip().lower()
    if t == "plus":
        return "pro"
    if t in VALID_PRODUCTS:
        return t  # type: ignore[return-value]
    if t == "free":
        return "free"
    return "free"


def tier_includes_ai(tier: SubscriptionTier) -> bool:
    return tier in ("ai", "pro")


def tier_includes_creator(tier: SubscriptionTier) -> bool:
    return tier in ("creator", "pro")


def subscription_entitlements(tier: SubscriptionTier) -> Dict[str, bool]:
    """Флаги возможностей для клиента."""
    return {
        "ad_free": tier != "free",
        "ai_scans_extended": tier_includes_ai(tier),
        "nutrition_ai_advanced": tier_includes_ai(tier),
        "ai_meal_plans": tier_includes_ai(tier),
        "meal_plan_free_days": 3,
        "meal_plan_ai_durations": [7, 14, 21, 30] if tier_includes_ai(tier) else [],
        "meal_plan_smart_shopping": tier_includes_ai(tier),
        "meal_plan_family": tier == "pro",
        "ai_recommendations": tier_includes_ai(tier),
        "ai_voice": tier_includes_ai(tier),
        "ai_priority_speed": tier_includes_ai(tier),
        "creator_analytics": tier_includes_creator(tier),
        "creator_promotion": tier_includes_creator(tier),
        "creator_tools": tier_includes_creator(tier),
        "creator_badge": tier_includes_creator(tier),
        "creator_pinned": tier_includes_creator(tier),
        "creator_scheduled_posts": tier_includes_creator(tier),
        "offline_recipes": tier_includes_ai(tier),
        "priority_support": tier == "pro",
        "exclusive_recipes": tier == "pro",
        # backward compat
        "is_plus": tier_includes_ai(tier),
    }


def subscription_status_payload(
    *,
    tier: SubscriptionTier,
    status: str,
    expires_at: Optional[Any],
    platform: Optional[str],
    auto_renew: bool,
    is_active: bool,
) -> Dict[str, Any]:
    ent = subscription_entitlements(tier)
    return {
        "subscription_type": tier,
        "subscription_status": status,
        "subscription_expire_at": expires_at.isoformat() if expires_at else None,
        "platform": platform,
        "auto_renew": auto_renew,
        "is_active": is_active,
        "is_plus": ent["is_plus"],
        "has_ai": tier_includes_ai(tier) and is_active,
        "has_creator": tier_includes_creator(tier) and is_active,
        "entitlements": ent,
    }
