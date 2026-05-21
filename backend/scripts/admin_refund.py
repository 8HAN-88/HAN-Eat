#!/usr/bin/env python3
"""
Провести возврат подписки от имени админа (ЮKassa).
Usage:
  ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=... \\
  SUBSCRIPTION_ID=42 BASE_URL=http://127.0.0.1:5001 \\
    python3 backend/scripts/admin_refund.py
Optional: REFUND_AMOUNT=199.00 REASON="..."
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
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return e.code, payload


def main() -> int:
    base = os.environ.get("BASE_URL", "http://127.0.0.1:5001").rstrip("/")
    email = os.environ.get("ADMIN_EMAIL", "").strip()
    password = os.environ.get("ADMIN_PASSWORD", "").strip()
    sub_id = os.environ.get("SUBSCRIPTION_ID", "").strip()

    if not email or not password or not sub_id:
        print("Set ADMIN_EMAIL, ADMIN_PASSWORD, SUBSCRIPTION_ID")
        return 1

    api = f"{base}/api/v1"
    code, data = _request(
        "POST",
        f"{api}/auth/login",
        body={"email": email, "password": password},
    )
    if code != 200 or not data.get("token"):
        print(f"FAIL login HTTP {code}: {data}")
        return 1

    auth = {"Authorization": f"Bearer {data['token']}"}
    body: dict = {"subscription_id": int(sub_id)}
    if os.environ.get("REFUND_AMOUNT"):
        body["amount"] = float(os.environ["REFUND_AMOUNT"])
    if os.environ.get("REASON"):
        body["reason"] = os.environ["REASON"]

    print(f"== admin refund subscription_id={sub_id} ==")
    code, result = _request(
        "POST",
        f"{api}/payments/admin/refund",
        headers=auth,
        body=body,
    )
    print(f"HTTP {code}", result)
    return 0 if code == 200 else 1


if __name__ == "__main__":
    sys.exit(main())
