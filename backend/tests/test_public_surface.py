"""Public HTTP surface: no OpenAPI, no loopback CORS, no infra dump."""
import asyncio

from app.core.public_surface import (
    cors_origins_for_env,
    docs_routes_for_env,
    frontend_return_url_allowed,
    google_readiness_public,
)


def test_payment_return_url_only_our_hosts():
    assert frontend_return_url_allowed(
        "https://haneat.app/subscription/success", "https://haneat.app"
    )
    assert frontend_return_url_allowed(
        "http://localhost:8080/paid/success", "https://haneat.app"
    )
    assert not frontend_return_url_allowed(
        "https://evil.example/steal", "https://haneat.app"
    )


def test_google_readiness_hides_skip_flag_in_production():
    payload = google_readiness_public(
        configured=True,
        skip_verification=False,
        client_ids_count=2,
        app_env="production",
    )
    assert payload["configured"] is True
    assert "skip_verification" not in payload
    assert "client_ids_count" not in payload


def test_docs_and_openapi_off_outside_development():
    prod = docs_routes_for_env("production")
    assert prod["docs_url"] is None
    assert prod["redoc_url"] is None
    assert prod["openapi_url"] is None
    dev = docs_routes_for_env("development")
    assert dev["openapi_url"] == "/openapi.json"


def test_production_cors_drops_loopback():
    origins = cors_origins_for_env(
        [
            "http://localhost:8080",
            "http://127.0.0.1:5000",
            "https://haneat.app",
        ],
        "production",
    )
    assert "http://localhost:8080" not in origins
    assert "http://127.0.0.1:5000" not in origins
    assert "https://haneat.app" in origins
    assert "https://www.haneat.app" in origins


def test_development_cors_keeps_loopback():
    origins = cors_origins_for_env(["http://localhost:8080"], "development")
    assert "http://localhost:8080" in origins


def test_database_error_is_generic(monkeypatch):
    from app.core import infrastructure_startup as infra

    class Boom:
        def connect(self):
            raise RuntimeError("password=super-secret host=10.0.0.8")

    monkeypatch.setattr(infra, "engine", Boom())
    ok, err = infra.check_database()
    assert ok is False
    assert err == "Database unreachable"
    assert "password" not in (err or "")
    assert "10.0.0.8" not in (err or "")


def test_system_readiness_omits_bucket_cdn_and_webhook(monkeypatch):
    from app.api.v1 import system as s

    monkeypatch.setattr(s, "collect_payments_issues", lambda: [])
    monkeypatch.setattr(s, "collect_media_issues", lambda: [])
    monkeypatch.setattr(s, "collect_production_issues", lambda: [])
    monkeypatch.setattr(s, "collect_infrastructure_issues", lambda: [])
    monkeypatch.setattr(
        s,
        "infrastructure_status",
        lambda: {
            "database": {"ok": True, "error": None},
            "redis": {"enabled": True, "ok": True, "error": None, "stub": False},
            "firebase": {"enabled": False, "push_ready": False, "issues": []},
        },
    )
    monkeypatch.setattr(s, "_s3_fully_configured", lambda: True)
    monkeypatch.setattr(s, "media_upload_mode", lambda: "s3")
    monkeypatch.setattr(s, "ffmpeg_available", lambda: True)

    payload = asyncio.run(s.system_readiness())
    media = payload["media"]
    payments = payload["payments"]
    assert "bucket" not in media
    assert "cdn_url" not in media
    assert "webhook_url" not in payments
    assert "bot_webhooks" not in payload
    assert payload["app_env"]
    assert "ready" in payload
