"""
Правила видимости рецептов: public (глобальный Menu/поиск/AI) vs private (только канал).
"""
from __future__ import annotations

from typing import Optional, Tuple

from fastapi import HTTPException, status
from sqlalchemy import and_

from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE
from app.models.community import Channel
from app.models.post import Post

RECIPE_VISIBILITY_PUBLIC = "public"
RECIPE_VISIBILITY_PRIVATE = "private"
RECIPE_VISIBILITIES = frozenset({RECIPE_VISIBILITY_PUBLIC, RECIPE_VISIBILITY_PRIVATE})

CHANNEL_VISIBILITY_MODE_PUBLIC = "public"
CHANNEL_VISIBILITY_MODE_PRIVATE = "private"
CHANNEL_VISIBILITY_MODE_MIXED = "mixed"
CHANNEL_VISIBILITY_MODES = frozenset(
    {
        CHANNEL_VISIBILITY_MODE_PUBLIC,
        CHANNEL_VISIBILITY_MODE_PRIVATE,
        CHANNEL_VISIBILITY_MODE_MIXED,
    }
)


def normalize_recipe_visibility(value: Optional[str]) -> str:
    if not value:
        return RECIPE_VISIBILITY_PUBLIC
    v = value.strip().lower()
    if v in RECIPE_VISIBILITIES:
        return v
    if v == "followers":
        return RECIPE_VISIBILITY_PUBLIC
    return RECIPE_VISIBILITY_PUBLIC


def normalize_channel_visibility_mode(value: Optional[str]) -> str:
    if not value:
        return CHANNEL_VISIBILITY_MODE_MIXED
    v = value.strip().lower()
    if v in CHANNEL_VISIBILITY_MODES:
        return v
    return CHANNEL_VISIBILITY_MODE_MIXED


def sync_recipe_index_flags(post: Post) -> None:
    """Денормализация для быстрых фильтров Menu/search/recommendations."""
    global_vis = (
        post.type == "recipe"
        and post.status == "published"
        and post.deleted_at is None
        and post.visibility == RECIPE_VISIBILITY_PUBLIC
        and not bool(post.hidden_from_recommendations)
    )
    post.is_global_visible = global_vis
    post.is_indexed = global_vis


def globally_visible_recipe_criteria():
    """SQLAlchemy filter: рецепт участвует в глобальном Menu/search/AI."""
    return and_(
        Post.type == "recipe",
        Post.status == "published",
        Post.deleted_at.is_(None),
        Post.is_global_visible.is_(True),
    )


def resolve_recipe_visibility(
    requested: Optional[str],
    channel: Optional[Channel],
    has_creator: bool,
) -> str:
    """
    Итоговая visibility с учётом режима канала и подписки Creator.
    """
    requested_norm = normalize_recipe_visibility(requested)

    if channel is None:
        if requested_norm == RECIPE_VISIBILITY_PRIVATE and not has_creator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": HAN_CREATOR_REQUIRED_CODE,
                    "message": "Приватные рецепты доступны с тарифом Creator или Pro",
                },
            )
        return requested_norm

    mode = normalize_channel_visibility_mode(
        getattr(channel, "recipe_visibility_mode", None)
    )

    if mode == CHANNEL_VISIBILITY_MODE_PUBLIC:
        return RECIPE_VISIBILITY_PUBLIC

    if mode == CHANNEL_VISIBILITY_MODE_PRIVATE:
        if not has_creator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": HAN_CREATOR_REQUIRED_CODE,
                    "message": "Приватный канал и приватные рецепты — тариф Creator или Pro",
                },
            )
        return RECIPE_VISIBILITY_PRIVATE

    # mixed — выбор автора
    if requested_norm == RECIPE_VISIBILITY_PRIVATE and not has_creator:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Приватные рецепты доступны с тарифом Creator или Pro",
            },
        )
    return requested_norm


def assert_can_create_private_channel(is_public: bool, has_creator: bool) -> None:
    if is_public is False and not has_creator:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Приватные каналы доступны с тарифом Creator или Pro",
            },
        )


def assert_can_set_channel_visibility_mode(mode: str, has_creator: bool) -> None:
    mode = normalize_channel_visibility_mode(mode)
    if mode in (
        CHANNEL_VISIBILITY_MODE_PRIVATE,
        CHANNEL_VISIBILITY_MODE_MIXED,
    ) and not has_creator:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Управление приватностью канала — тариф Creator или Pro",
            },
        )


def invalidate_recipe_search_cache() -> None:
    """Best-effort: сброс кэша рекомендаций Menu при смене visibility."""
    try:
        from app.core.redis_client import redis_client

        for key in redis_client.scan_iter("recipes:recommendations:*"):
            redis_client.delete(key)
        for key in redis_client.scan_iter("recipes:search:*"):
            redis_client.delete(key)
    except Exception:
        pass
