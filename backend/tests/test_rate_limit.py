"""Rate limit middleware helpers."""
from app.middleware.rate_limit import _client_ip, _is_exempt, _is_read_heavy_get


def test_exempt_paths():
    assert _is_exempt("/health") is True
    assert _is_exempt("/api/v1/system/readiness") is True
    assert _is_exempt("/api/v1/payments/webhook/yookassa") is True
    assert _is_exempt("/privacy") is True
    assert _is_exempt("/api/v1/feed") is False
    assert _is_exempt("/api/v1/auth/login") is False
    assert _is_exempt("/api/v1/uploads/file/uploads/x.jpg") is True
    assert _is_exempt("/api/v1/uploads/init", "POST") is False
    assert _is_exempt("/api/v1/uploads/complete", "POST") is False


def test_inbox_gets_are_not_ip_capped():
    assert _is_read_heavy_get("GET", "/api/v1/chats") is True
    assert _is_read_heavy_get("GET", "/api/v1/chats/join-requests/inbox") is True
    assert _is_read_heavy_get("GET", "/api/v1/channels") is True
    assert _is_read_heavy_get("GET", "/api/v1/feed") is True
    assert _is_read_heavy_get("POST", "/api/v1/chats") is False
    assert _is_read_heavy_get("GET", "/api/v1/auth/login") is False


def test_client_ip_from_forwarded():
    class FakeClient:
        host = "10.0.0.1"

    class FakeRequest:
        client = FakeClient()
        headers = {"x-forwarded-for": "203.0.113.5, 10.0.0.1"}

    # Last hop is the address the proxy appended, not a client-supplied first value.
    assert _client_ip(FakeRequest()) == "10.0.0.1"


def test_client_ip_prefers_real_ip():
    class FakeClient:
        host = "10.0.0.1"

    class FakeRequest:
        client = FakeClient()
        headers = {
            "x-real-ip": "198.51.100.9",
            "x-forwarded-for": "203.0.113.5, 10.0.0.1",
        }

    assert _client_ip(FakeRequest()) == "198.51.100.9"


def test_client_ip_ignores_forwarded_from_public_peer():
    class FakeClient:
        host = "203.0.113.9"

    class FakeRequest:
        client = FakeClient()
        headers = {
            "x-real-ip": "198.51.100.9",
            "x-forwarded-for": "203.0.113.5",
        }

    assert _client_ip(FakeRequest()) == "203.0.113.9"
