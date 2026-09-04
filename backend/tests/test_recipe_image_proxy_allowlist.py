from app.api.v1.recipes import _proxy_allowed_image_url


def test_own_cdn_is_allowed_for_image_proxy():
    assert _proxy_allowed_image_url(
        "https://cdn.haneat.com/uploads/user_2/2025/06/05/abc.jpg"
    )
    assert _proxy_allowed_image_url(
        "https://cdn.haneat.app/uploads/user_2/2025/06/05/abc.jpg"
    )


def test_random_host_is_rejected():
    assert not _proxy_allowed_image_url("https://evil.example/x.jpg")
    assert not _proxy_allowed_image_url("http://cdn.haneat.com/x.jpg")
