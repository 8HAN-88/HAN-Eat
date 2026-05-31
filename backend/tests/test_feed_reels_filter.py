"""Проверка фильтра ленты reels (type=reel или видео в media)."""
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
    query = MagicMock()
    FeedService._apply_feed_type_filter(query, "photos")
    query.filter.assert_called_once()
