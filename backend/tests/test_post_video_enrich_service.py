"""Тесты обогащения video media в постах."""
from app.services.post_video_enrich_service import (
    enrich_post_body_video_media,
    extract_file_key_from_video_url,
    extract_upload_id_from_video_url,
)


def test_extract_upload_id():
    url = (
        "https://api.haneat.app/api/v1/uploads/file/"
        "uploads/user_1/2024/01/01/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.mp4"
    )
    assert extract_upload_id_from_video_url(url) == (
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )


def test_extract_file_key_strips_transcode_suffix():
    url = (
        "https://cdn.haneat.app/uploads/user_1/2024/01/01/"
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee_720p.mp4"
    )
    assert extract_file_key_from_video_url(url) == (
        "uploads/user_1/2024/01/01/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.mp4"
    )


class _Proc:
    def __init__(self):
        self.upload_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.file_key = (
            "uploads/user_1/2024/01/01/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.mp4"
        )
        self.status = "completed"
        self.mp4_1080p_url = "https://cdn/1080.mp4"
        self.mp4_480p_url = "https://cdn/480.mp4"
        self.mp4_720p_url = "https://cdn/720.mp4"
        self.hls_url = "https://cdn/hls/playlist.m3u8"
        self.thumbnail_url = "https://cdn/thumb.jpg"


class _Query:
    def __init__(self, rows):
        self._rows = rows

    def filter(self, *_args, **_kwargs):
        return self

    def all(self):
        return self._rows


class _Db:
    def __init__(self, rows):
        self._rows = rows

    def query(self, _model):
        return _Query(self._rows)


def test_enrich_post_body_adds_transcoded_urls():
    proc = _Proc()
    file_key = proc.file_key
    body = {
        "media": [
            {
                "type": "video",
                "url": f"https://api.haneat.app/{file_key}",
            }
        ]
    }
    enriched = enrich_post_body_video_media(_Db([proc]), body)
    video = enriched["media"][0]
    assert video["mp4_1080p_url"] == "https://cdn/1080.mp4"
    assert video["mp4_480p_url"] == "https://cdn/480.mp4"
    assert video["mp4_720p_url"] == "https://cdn/720.mp4"
    assert video["hls_url"] == "https://cdn/hls/playlist.m3u8"
    assert video["thumbnail_url"] == "https://cdn/thumb.jpg"
    assert video["url"] == f"https://api.haneat.app/{file_key}"
