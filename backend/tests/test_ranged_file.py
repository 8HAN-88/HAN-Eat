import os
import tempfile

import pytest
from starlette.requests import Request

from app.core.ranged_file import ranged_file_response


def _make_request(method: str = "GET", headers=None) -> Request:
    hdrs = []
    for k, v in (headers or {}).items():
        hdrs.append((k.lower().encode(), v.encode()))
    scope = {
        "type": "http",
        "method": method,
        "path": "/",
        "headers": hdrs,
    }
    return Request(scope)


def test_ranged_file_returns_206_for_partial_range():
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(b"0123456789abcdef")
        path = tmp.name
    try:
        resp = ranged_file_response(
            path,
            _make_request(headers={"Range": "bytes=0-3"}),
            media_type="video/mp4",
        )
        assert resp.status_code == 206
        assert resp.headers["content-range"] == "bytes 0-3/16"
        assert resp.body == b"0123"
    finally:
        os.unlink(path)


def test_ranged_file_sets_accept_ranges_on_full_response():
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(b"hello")
        path = tmp.name
    try:
        resp = ranged_file_response(
            path,
            _make_request(),
            media_type="video/mp4",
        )
        assert resp.status_code == 200
        assert resp.headers["accept-ranges"] == "bytes"
    finally:
        os.unlink(path)
