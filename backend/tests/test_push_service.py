"""FCM data payload для навигации в Flutter."""
from app.models.notification import Notification
from app.services.push_service import PushService


def test_build_fcm_data_channel_post():
    notification = Notification(
        user_id=1,
        type="channel_recipe",
        entity_type="channel",
        entity_id=10,
        actor_id=5,
        title="New recipe",
        body="Test",
        data={
            "channel_id": 10,
            "post_id": 99,
            "post_type": "recipe",
        },
    )
    data = PushService._build_fcm_data(notification)
    assert data["type"] == "channel_recipe"
    assert data["channel_id"] == "10"
    assert data["post_id"] == "99"
    assert data["post_type"] == "recipe"
    assert data["actor_id"] == "5"


def test_build_fcm_data_subscription_route():
    notification = Notification(
        user_id=1,
        type="subscription_expiring",
        entity_type="subscription",
        entity_id=0,
        actor_id=None,
        title="Expiring",
        body="Soon",
        data={},
    )
    data = PushService._build_fcm_data(notification)
    assert data["route"] == "subscription"
    assert data["type"] == "subscription_expiring"
