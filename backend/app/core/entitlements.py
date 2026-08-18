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
HAN_FEATURE_REQUIRED_CODE = "HAN_FEATURE_REQUIRED"
LOGIN_REQUIRED_CODE = "LOGIN_REQUIRED"

CATALOG_FEATURE_SLUGS = (
    "ad_free",
    "exclusive_reactions",
    "profile_decoration",
    "ai_recommendations",
    "ai_priority_speed",
    "offline_saved_posts",
    "creator_tools",
    "creator_scheduled_posts",
    "creator_analytics",
    "priority_support",
    "chat_translation",
    "extra_pins",
    "larger_uploads",
    "privacy_plus",
    "extra_folders",
    "message_effects",
    "scheduled_messages",
    "chat_wallpaper",
    "story_viewers",
    "story_close_friends",
    "gif_search",
    "animated_stickers",
    "group_readers",
    "live_location",
)

EXCLUSIVE_CHAT_REACTIONS = frozenset({"🔥", "🥰", "🎉", "✨", "⚡️", "💯"})


def feature_required_detail(slug: str, message: str) -> Dict[str, str]:
    return {
        "code": HAN_FEATURE_REQUIRED_CODE,
        "feature": slug,
        "message": message,
    }


def catalog_entitlements(slugs: set[str]) -> Dict[str, bool]:
    unlocked = {str(s) for s in slugs}
    ents = {key: key in unlocked for key in CATALOG_FEATURE_SLUGS}
    ents["premium_badge"] = ents["profile_decoration"]
    ents["is_plus"] = ents["ai_recommendations"] or ents["ai_priority_speed"]
    ents["pro"] = ents["priority_support"]
    ents["offline_recipes"] = ents["offline_saved_posts"]
    ents["creator_promotion"] = ents["creator_tools"]
    ents["creator_pinned"] = ents["creator_tools"]
    ents["creator_badge"] = ents["creator_tools"]
    ents["advanced_stats"] = ents["creator_analytics"]
    ents["priority_reels_quality"] = ents["ai_priority_speed"]
    return ents

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
        # Messenger AI helpers (no kitchen scans / meal plans).
        "ai_priority_speed": tier_includes_ai(tier),
        "ai_recommendations": tier_includes_ai(tier),
        "creator_analytics": tier_includes_creator(tier),
        "creator_promotion": tier_includes_creator(tier),
        "creator_tools": tier_includes_creator(tier),
        "creator_badge": tier_includes_creator(tier),
        "creator_pinned": tier_includes_creator(tier),
        "creator_scheduled_posts": tier_includes_creator(tier),
        "offline_saved_posts": tier_includes_ai(tier),
        "offline_recipes": tier_includes_ai(tier),  # legacy alias
        "pro": tier == "pro",
        "priority_support": tier == "pro",
        "premium_badge": tier != "free",
        "exclusive_reactions": tier != "free",
        "profile_decoration": tier != "free",
        "larger_uploads": tier != "free",
        "priority_reels_quality": tier != "free",
        "advanced_stats": tier_includes_creator(tier),
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
