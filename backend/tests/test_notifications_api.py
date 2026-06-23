"""API notifications list enriches post previews."""
from app.models.post import Post
from app.services.notification_preview_service import post_preview_for_notifications


def test_post_preview_for_notifications_recipe():
    post = Post(
        id=5,
        user_id=1,
        type="recipe",
        body={"image": "/media/r.jpg"},
    )
    preview = post_preview_for_notifications(post)
    assert preview["post_type"] == "recipe"
    assert preview["thumbnail_url"] is not None


def test_post_preview_for_photo_media():
    post = Post(
        id=5,
        user_id=1,
        type="photo",
        body={"media": [{"type": "image", "url": "/m.jpg"}]},
    )
    preview = post_preview_for_notifications(post)
    assert preview["thumbnail_url"] is not None
    assert preview["post_type"] == "photo"
