"""Checklist items that are pure functions: headers, cookies, upload denylist."""
from app.core.http_security import (
    content_security_policy_for,
    database_url_is_open_default,
    harden_set_cookie,
    security_headers,
)
from app.core.upload_policy import (
    document_octet_stream_allowed,
    upload_block_reason,
    video_cap_megabytes,
)


def test_api_headers_include_csp_frame_and_nosniff():
    headers = security_headers(content_type="application/json", https=True)
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in headers["Content-Security-Policy"]
    assert headers["Strict-Transport-Security"].startswith("max-age=")


def test_http_responses_do_not_send_hsts():
    headers = security_headers(content_type="application/json", https=False)
    assert "Strict-Transport-Security" not in headers


def test_html_csp_allows_flutter_and_blocks_objects():
    policy = content_security_policy_for("text/html; charset=utf-8")
    assert "script-src 'self'" in policy
    assert "object-src 'none'" in policy
    assert "frame-ancestors 'self'" in policy


def test_cookie_gains_httponly_samesite_and_secure_on_https():
    hardened = harden_set_cookie("sid=abc", https=True)
    assert "HttpOnly" in hardened
    assert "SameSite=Lax" in hardened
    assert "Secure" in hardened


def test_cookie_secure_is_not_forced_on_plain_http():
    hardened = harden_set_cookie("sid=abc; HttpOnly; SameSite=Lax", https=False)
    assert "Secure" not in hardened


def test_executable_and_html_uploads_are_blocked():
    assert upload_block_reason("application/octet-stream", "virus.exe")
    assert upload_block_reason("text/html", "page.html")
    assert upload_block_reason("image/svg+xml", "icon.svg")
    assert upload_block_reason("application/javascript", "app.js")
    assert upload_block_reason("image/jpeg", "photo.jpg") is None


def test_octet_stream_needs_a_document_name():
    assert document_octet_stream_allowed("application/octet-stream", "notes.pdf")
    assert document_octet_stream_allowed("application/octet-stream", "virus.exe") is False
    assert document_octet_stream_allowed("application/octet-stream", None) is False
    assert document_octet_stream_allowed("application/pdf", None)


def test_video_without_a_configured_cap_uses_the_nginx_ceiling():
    assert video_cap_megabytes(0) == 64
    assert video_cap_megabytes(32) == 32


def test_sample_database_url_is_not_a_production_database():
    assert database_url_is_open_default("postgresql://user:password@localhost:5432/haneat")
    assert database_url_is_open_default("sqlite:///./dev.db")
    assert database_url_is_open_default("")
    assert database_url_is_open_default(
        "postgresql://haneat:real-secret@127.0.0.1:5432/haneat"
    ) is False
