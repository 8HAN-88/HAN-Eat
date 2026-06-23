"""Post thumbnail extraction for notifications."""
from app.models.post import Post
from app.services.notification_preview_service import post_thumbnail_url


def test_post_thumbnail_from_image_media():
    post = Post(
        id=1,
        user_id=1,
        type="photo",
        body={"media": [{"type": "image", "url": "/media/photo.jpg"}]},
    )
    url = post_thumbnail_url(post)
    assert url is not None
    assert "photo.jpg" in url


def test_post_thumbnail_from_recipe_image():
    post = Post(
        id=2,
        user_id=1,
        type="recipe",
        body={"image": "/media/recipe.jpg"},
    )
    url = post_thumbnail_url(post)
    assert url is not None
    assert "recipe.jpg" in url
