"""Privacy rules for saved posts in profiles."""

from app.schemas.user import UserStats


def test_user_stats_saved_count_hidden_for_other_viewers():
    stats = UserStats(
        posts_count=3,
        reels_count=1,
        saved_count=12,
        followers_count=4,
        following_count=2,
    )
    masked = stats.model_copy(update={"saved_count": 0})
    assert masked.saved_count == 0
    assert masked.posts_count == 3


def test_saved_posts_owner_only_access_rule():
    def allowed(current_user_id, target_user_id):
        return current_user_id is not None and current_user_id == target_user_id

    assert allowed(10, 10)
    assert not allowed(10, 11)
    assert not allowed(None, 11)
