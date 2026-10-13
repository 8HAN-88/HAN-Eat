import pytest
from fastapi import HTTPException

from app.api.v1 import recipes as r
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


def test_proxy_fetch_does_not_follow_redirects(monkeypatch):
    seen = {}

    class FakeResp:
        status_code = 302
        headers = {"Location": "http://127.0.0.1/secret", "Content-Type": "image/jpeg"}
        content = b""

    def fake_get(*args, **kwargs):
        seen.update(kwargs)
        return FakeResp()

    monkeypatch.setattr(r.requests, "get", fake_get)
    with pytest.raises(HTTPException) as exc:
        r._fetch_proxied_image("https://cdn.haneat.app/x.jpg")
    assert exc.value.status_code == 400
    assert seen.get("allow_redirects") is False


def test_proxy_fetch_rejects_non_image(monkeypatch):
    class FakeResp:
        status_code = 200
        headers = {"Content-Type": "text/html"}
        content = b"<html></html>"

    monkeypatch.setattr(r.requests, "get", lambda *a, **k: FakeResp())
    with pytest.raises(HTTPException) as exc:
        r._fetch_proxied_image("https://cdn.haneat.app/x.jpg")
    assert exc.value.status_code == 400
