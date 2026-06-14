"""Проверка MIME-типов видео при инициализации загрузки."""
from unittest.mock import patch

import pytest

from app.services.media_service import (
    MediaService,
    _is_allowed_video_content_type,
    _video_extension_from_content_type,
)


def test_quicktime_mime_is_allowed():
    assert _is_allowed_video_content_type("video/quicktime") is True


def test_mp4_mime_is_allowed():
    assert _is_allowed_video_content_type("video/mp4") is True


def test_webm_mime_is_allowed():
    assert _is_allowed_video_content_type("video/webm") is True


def test_webm_maps_to_webm_extension():
    assert _video_extension_from_content_type("video/webm") == "webm"


def test_quicktime_maps_to_mov_extension():
    assert _video_extension_from_content_type("video/quicktime") == "mov"


@patch.object(MediaService, "_init_s3_client", return_value=None)
def test_generate_presigned_url_accepts_quicktime(mock_s3):
    svc = MediaService()
    result = svc.generate_presigned_url(
        file_type="video",
        content_type="video/quicktime",
        file_size=1024,
        user_id=42,
    )
    assert result["file_key"].endswith(".mov")
