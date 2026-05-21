#!/usr/bin/env python3
"""
Smoke: admin refund API access control + queue shape.
Usage:
  SMOKE_EMAIL=user@example.com SMOKE_PASSWORD=secret \\
  ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=secret \\
    python3 backend/scripts/smoke_admin_refunds.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def _request(method: str, url: str, headers: dict | None = None, body: dict | None = None):
    data = None
    hdrs = {"Content-Type": "application/json", **(headers or {})}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return e.code, payload


def _login(api: str, email: str, password: str) -> dict[str, str] | None:
    code, data = _request(
        "POST",
        f"{api}/auth/login",
        body={"email": email, "password": password},
    )
    if code == 200 and data.get("token"):
        return {"Authorization": f"Bearer {data['token']}"}
    return None


def main() -> int:
    base = os.environ.get("BASE_URL", "http://127.0.0.1:5001").rstrip("/")
    api = f"{base}/api/v1"

    user_email = os.environ.get("SMOKE_EMAIL", "").strip()
    user_pass = os.environ.get("SMOKE_PASSWORD", "").strip()
    admin_email = os.environ.get("ADMIN_EMAIL", "").strip()
    admin_pass = os.environ.get("ADMIN_PASSWORD", "").strip()

    if not user_email or not user_pass:
        print("SKIP: set SMOKE_EMAIL and SMOKE_PASSWORD")
        return 0

    user_auth = _login(api, user_email, user_pass)
    if not user_auth:
        print("FAIL: user login")
        return 1

    print("== user GET /payments/admin/refund-queue (expect 403) ==")
    code, body = _request(
        "GET", f"{api}/payments/admin/refund-queue", headers=user_auth
    )
    print(f"HTTP {code}")
    if code != 403:
        print(f"FAIL: expected 403 for non-admin, got {code}: {body}")
        return 1
    print("OK non-admin denied")

    if not admin_email or not admin_pass:
        print("SKIP admin checks (set ADMIN_EMAIL, ADMIN_PASSWORD)")
        return 0

    admin_auth = _login(api, admin_email, admin_pass)
    if not admin_auth:
        print("FAIL: admin login")
        return 1

    print("== admin GET /payments/admin/refund-queue ==")
    code, queue = _request(
        "GET", f"{api}/payments/admin/refund-queue", headers=admin_auth
    )
    print(f"HTTP {code} total={queue.get('total')}")
    if code != 200:
        print(f"FAIL: {queue}")
        return 1
    if "items" not in queue:
        print(f"FAIL: missing items key: {queue}")
        return 1
    print("OK admin refund queue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
