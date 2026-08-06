"""Tenor GIF catalog proxy (service layer)."""
import pytest

from app.schemas.gif import GifItemResponse, GifSearchResponse
from app.services import gif_search_service


@pytest.mark.asyncio
async def test_search_without_tenor_key_returns_unconfigured(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "")
    result = await gif_search_service.search_gifs(query="cats", limit=12)
    assert result.configured is False
    assert result.items == []


@pytest.mark.asyncio
async def test_featured_without_tenor_key_returns_unconfigured(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "")
    result = await gif_search_service.featured_gifs(limit=12)
    assert result.configured is False
    assert result.items == []


@pytest.mark.asyncio
async def test_search_empty_query_returns_empty_when_configured(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "test-key")
    result = await gif_search_service.search_gifs(query="  ", limit=8)
    assert result.configured is True
    assert result.items == []


@pytest.mark.asyncio
async def test_search_maps_tenor_payload(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "test-key")
    monkeypatch.setattr(gif_search_service.settings, "TENOR_CLIENT_KEY", "hanwe")

    async def _fake_get(path, params):
        assert path == "search"
        assert params["q"] == "hello"
        assert params["limit"] == 8
        return {
            "next": "cursor-2",
            "results": [
                {
                    "id": "t1",
                    "title": "Wave",
                    "media_formats": {
                        "gif": {
                            "url": "https://media.tenor.com/x.gif",
                            "dims": [320, 240],
                        },
                        "tinygif": {
                            "url": "https://media.tenor.com/x-tiny.gif",
                            "dims": [160, 120],
                        },
                    },
                },
                {
                    "id": "bad",
                    "media_formats": {},
                },
            ],
        }

    monkeypatch.setattr(gif_search_service, "_tenor_get", _fake_get)

    result = await gif_search_service.search_gifs(query="hello", limit=8)
    assert result.configured is True
    assert result.next == "cursor-2"
    assert len(result.items) == 1
    item = result.items[0]
    assert item.id == "t1"
    assert item.url == "https://media.tenor.com/x.gif"
    assert item.preview_url == "https://media.tenor.com/x-tiny.gif"
    assert item.width == 320
    assert item.height == 240


@pytest.mark.asyncio
async def test_featured_maps_tenor_payload(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "test-key")

    async def _fake_get(path, params):
        assert path == "featured"
        return {
            "next": "",
            "results": [
                {
                    "id": "f1",
                    "content_description": "Featured",
                    "media_formats": {
                        "gif": {"url": "https://media.tenor.com/f.gif", "dims": [100, 80]},
                        "nanogif": {"url": "https://media.tenor.com/f-nano.gif"},
                    },
                },
            ],
        }

    monkeypatch.setattr(gif_search_service, "_tenor_get", _fake_get)
    result = await gif_search_service.featured_gifs(limit=10)
    assert isinstance(result, GifSearchResponse)
    assert result.next is None
    assert result.items[0].title == "Featured"
    assert isinstance(result.items[0], GifItemResponse)


@pytest.mark.asyncio
async def test_search_tenor_error_propagates(monkeypatch):
    monkeypatch.setattr(gif_search_service.settings, "TENOR_API_KEY", "test-key")

    async def _boom(*_args, **_kwargs):
        raise RuntimeError("tenor down")

    monkeypatch.setattr(gif_search_service, "_tenor_get", _boom)

    with pytest.raises(RuntimeError, match="tenor down"):
        await gif_search_service.search_gifs(query="x", limit=5)


def test_item_from_tenor_requires_urls():
    assert gif_search_service._item_from_tenor({"id": "1"}) is None
    item = gif_search_service._item_from_tenor(
        {
            "id": "2",
            "title": "ok",
            "media_formats": {
                "gif": {"url": "https://media.tenor.com/a.gif"},
            },
        }
    )
    assert item is not None
    assert item.preview_url == item.url
