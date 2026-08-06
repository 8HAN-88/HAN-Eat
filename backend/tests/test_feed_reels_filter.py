"""Проверка фильтра ленты reels (type=reel или видео в media)."""
from types import SimpleNamespace
from unittest.mock import MagicMock

from app.services.feed_service import FeedService


def test_apply_feed_type_filter_reels_uses_or_clause():
    query = MagicMock()
    FeedService._apply_feed_type_filter(query, "reels")
    query.filter.assert_called_once()
    # or_(Post.type == "reel", video_in_media)
    clause = query.filter.call_args[0][0]
    assert getattr(clause, "operator", None).__name__ == "or_"


def test_apply_feed_type_filter_all_returns_query_unchanged():
    query = MagicMock()
    assert FeedService._apply_feed_type_filter(query, "all") is query
    query.filter.assert_not_called()


def test_apply_feed_type_filter_photos_filters_type():
    from app.models.post import Post

    query = MagicMock()
    FeedService._apply_feed_type_filter(query, "photos")
    query.filter.assert_called_once()
    clause = query.filter.call_args[0][0]
    assert str(clause) == str(Post.type == "photo")


def test_apply_feed_type_filter_recipes_is_noop_legacy():
    """Legacy kitchen feed_type=recipes no longer filters — messenger shows all."""
    query = MagicMock()
    assert FeedService._apply_feed_type_filter(query, "recipes") is query
    query.filter.assert_not_called()


def test_diversity_guard_limits_repeated_authors_in_recommendations():
    service = FeedService(MagicMock(), MagicMock())
    posts = [
        SimpleNamespace(id=1, user_id=10, channel_id=None, type="recipe"),
        SimpleNamespace(id=2, user_id=10, channel_id=None, type="recipe"),
        SimpleNamespace(id=3, user_id=11, channel_id=None, type="photo"),
        SimpleNamespace(id=4, user_id=10, channel_id=None, type="recipe"),
    ]

    ranked = service._apply_diversity_guard(
        [(10.0 - idx, post) for idx, post in enumerate(posts)],
        following_only=False,
    )

    assert [p.id for p in ranked[:2]] == [1, 3]


def test_invalidate_feed_cache_deletes_all_feed_variants():
    redis = MagicMock()
    service = FeedService(MagicMock(), redis)

    service.invalidate_feed_cache(user_id=42, feed_type="reels")

    deleted_keys = [call.args[0] for call in redis.delete.call_args_list]
    assert "feed:v2:42:reels:following_only=True:sort=personalized:hide_promo=True" in deleted_keys
    assert "feed:42:reels:following_only=True:hide_promo=True" in deleted_keys
    assert "feed:42:reels:following_only=False:hide_promo=False" in deleted_keys
    assert "feed:42:reels:following_only=True" in deleted_keys
    assert "feed:42:reels:following_only=False" in deleted_keys
