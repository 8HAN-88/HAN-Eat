"""Channel posts Redis cache is dropped after a write."""
from unittest.mock import MagicMock, patch

from app.services.channel_posts_cache import invalidate_channel_posts_cache


def test_invalidate_channel_posts_cache_deletes_matching_keys():
    redis = MagicMock()
    redis.scan_iter.return_value = [
        "channel_posts:7:all:no_search:20:0:user_1",
        "channel_posts:7:text:no_search:20:0",
    ]
    with patch(
        "app.core.redis_client.REDIS_IS_STUB",
        False,
    ), patch(
        "app.core.redis_client.get_redis",
        return_value=redis,
    ):
        invalidate_channel_posts_cache(7)

    redis.scan_iter.assert_called_once()
    redis.delete.assert_called_once()
    deleted = redis.delete.call_args[0]
    assert "channel_posts:7:all:no_search:20:0:user_1" in deleted


def test_invalidate_skips_stub_redis():
    with patch("app.core.redis_client.REDIS_IS_STUB", True):
        invalidate_channel_posts_cache(3)
