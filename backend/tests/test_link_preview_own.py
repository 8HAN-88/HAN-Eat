"""Own HanWe reel/post URLs build a rich preview from the post, not the SPA."""
from types import SimpleNamespace

from app.models.post import Post
from app.services.link_preview_service import (
    parse_own_content_url,
    preview_from_post,
    render_own_og_html,
    try_own_content_preview,
)


def test_parse_own_reel_and_post_urls():
    assert parse_own_content_url("https://haneat.app/reel/28") == ("reel", 28)
    assert parse_own_content_url("https://haneat.app/app/reel/28") == ("reel", 28)
    assert parse_own_content_url("https://www.haneat.app/reel/28/") == ("reel", 28)
    assert parse_own_content_url("haneat://reel/28") == ("reel", 28)
    assert parse_own_content_url("/reel/28") == ("reel", 28)
    assert parse_own_content_url("https://haneat.app/post/7") == ("post", 7)
    assert parse_own_content_url("https://api.haneat.app/app/post/7") == ("post", 7)


def test_parse_own_content_ignores_foreign_and_other_paths():
    assert parse_own_content_url("https://yandex.ru/pogoda") is None
    assert parse_own_content_url("https://haneat.app/feed") is None
    assert parse_own_content_url("https://haneat.app/reels") is None
    assert parse_own_content_url("https://example.com/reel/28") is None
    assert parse_own_content_url("") is None


def test_preview_from_reel_uses_caption_author_and_thumb():
    post = Post(
        id=28,
        user_id=1,
        type="reel",
        title=None,
        description="салют",
        visibility="public",
        body={"video_thumbnail": "/media/reel-28.jpg"},
    )
    post.user = SimpleNamespace(name="Максим", username="max")
    preview = preview_from_post(post, canonical_url="https://haneat.app/reel/28")
    assert preview["url"] == "https://haneat.app/reel/28"
    assert preview["title"] == "салют"
    assert preview["description"] == "Максим в HanWe"
    assert preview["site_name"] == "HanWe"
    assert preview["image_url"]
    assert "reel-28.jpg" in preview["image_url"]


def test_preview_from_reel_without_caption_falls_back_to_author():
    post = Post(
        id=3,
        user_id=1,
        type="reel",
        title=None,
        description=None,
        visibility="public",
        body={},
    )
    post.user = SimpleNamespace(name="Анна", username="anna")
    preview = preview_from_post(post, canonical_url="https://haneat.app/reel/3")
    assert preview["title"] == "Рилс · Анна"
    assert preview["description"] == "Анна в HanWe"


def test_og_html_contains_title_image_and_app_redirect():
    html = render_own_og_html(
        {
            "url": "https://haneat.app/reel/28",
            "title": "салют",
            "description": "Максим в HanWe",
            "image_url": "https://cdn.example/thumb.jpg",
            "site_name": "HanWe",
        },
        kind="reel",
        post_id=28,
    )
    assert 'property="og:title" content="салют"' in html
    assert 'property="og:image" content="https://cdn.example/thumb.jpg"' in html
    assert 'property="og:type" content="video.other"' in html
    assert "/app/reel/28" in html


def test_try_own_content_preview_skips_private_and_missing():
    class _Query:
        def options(self, *_a, **_k):
            return self

        def filter(self, *_a, **_k):
            return self

        def first(self):
            return None

    class _Db:
        def query(self, *_a, **_k):
            return _Query()

    assert try_own_content_preview(_Db(), "https://haneat.app/reel/99") is None
    assert try_own_content_preview(_Db(), "https://yandex.ru/pogoda") is None


def test_try_own_content_preview_hides_private_posts():
    private = Post(
        id=4,
        user_id=1,
        type="reel",
        visibility="private",
        deleted_at=None,
        body={},
    )
    private.user = SimpleNamespace(name="Hidden", username="h")

    class _Query:
        def options(self, *_a, **_k):
            return self

        def filter(self, *_a, **_k):
            return self

        def first(self):
            return private

    class _Db:
        def query(self, *_a, **_k):
            return _Query()

    assert try_own_content_preview(_Db(), "https://haneat.app/reel/4") is None
