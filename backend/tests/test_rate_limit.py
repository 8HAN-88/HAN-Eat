"""Rate limit middleware helpers."""
from app.middleware.rate_limit import _client_ip, _is_exempt


def test_exempt_paths():
    assert _is_exempt("/health") is True
    assert _is_exempt("/api/v1/system/readiness") is True
    assert _is_exempt("/api/v1/payments/webhook/yookassa") is True
    assert _is_exempt("/privacy") is True
    assert _is_exempt("/api/v1/feed") is False
    assert _is_exempt("/api/v1/auth/login") is False


def test_client_ip_from_forwarded():
    class FakeClient:
        host = "10.0.0.1"

    class FakeRequest:
        client = FakeClient()
        headers = {"x-forwarded-for": "203.0.113.5, 10.0.0.1"}

    assert _client_ip(FakeRequest()) == "203.0.113.5"
