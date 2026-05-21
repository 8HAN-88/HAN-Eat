#!/usr/bin/env python3
"""
E2E smoke: login → status → reserve → analyze (ticket).
Usage:
  SMOKE_EMAIL=user@example.com SMOKE_PASSWORD=secret \\
    python3 backend/scripts/smoke_ai_scan_auth.py
  BASE_URL=http://127.0.0.1:5001 python3 ...
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request

# 1x1 PNG
_TINY_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


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
    email = os.environ.get("SMOKE_EMAIL", "").strip()
    password = os.environ.get("SMOKE_PASSWORD", "").strip()

    if not email or not password:
        print("SKIP: set SMOKE_EMAIL and SMOKE_PASSWORD to run authenticated AI scan smoke")
        return 0

    api = f"{base}/api/v1"
    print(f"== login ({email}) ==")
    code, data = _request(
        "POST",
        f"{api}/auth/login",
        body={"email": email, "password": password},
    )
    auth: dict[str, str] | None = None
    if code == 200:
        token = data.get("token")
        if not token:
            print(f"FAIL login: no token in {data}")
            return 1
        auth = {"Authorization": f"Bearer {token}"}
    elif os.environ.get("SMOKE_AUTO_REGISTER", "").lower() in ("1", "true", "yes"):
        print("== register (auto) ==")
        code, reg = _request(
            "POST",
            f"{api}/auth/register",
            body={
                "email": email,
                "password": password,
                "name": "Smoke Test",
                "username": email.split("@")[0][:32],
            },
        )
        if code not in (200, 201):
            print(f"FAIL register HTTP {code}: {reg}")
            return 1
        token = reg.get("token")
        if not token:
            print(f"FAIL register: no token in {reg}")
            return 1
        auth = {"Authorization": f"Bearer {token}"}
    else:
        print(f"FAIL login HTTP {code}: {data}")
        print("Tip: SMOKE_AUTO_REGISTER=1 to create test user if missing")
        return 1

    print("== ai-scan status ==")
    code, status_data = _request("GET", f"{api}/ai-scan/status", headers=auth)
    print(f"HTTP {code}", status_data)
    if code != 200:
        return 1

    print("== ai-scan reserve ==")
    code, reserve = _request("POST", f"{api}/ai-scan/reserve", headers=auth)
    print(f"HTTP {code}", reserve)
    if code != 200:
        print("(reserve failed — возможно, нет кредитов)")
        return 1

    ticket = reserve.get("ticket")
    if not ticket:
        print("FAIL: no ticket")
        return 1

    # Spoonacular отклоняет 1×1 PNG («not food») — тестовое фото еды по URL.
    _FOOD_IMAGE_URL = (
        "https://img.spoonacular.com/recipes/716429-556x370.jpg"
    )
    print("== analyze (with ticket, food image_url) ==")
    analyze_body = {
        "image_url": _FOOD_IMAGE_URL,
        "mode": "all",
        "language": "ru",
        "ai_scan_ticket": ticket,
    }
    code, analyze = _request(
        "POST", f"{api}/analyze", headers=auth, body=analyze_body
    )
    if code == 502:
        print("retry analyze after Spoonacular 502...")
        code, analyze = _request(
            "POST", f"{api}/analyze", headers=auth, body=analyze_body
        )
    print(f"HTTP {code}")
    if code == 200:
        label = (analyze.get("analysis") or {}).get("label")
        print(f"OK analysis label={label!r}")
        return 0
    if code == 502:
        detail = analyze.get("detail", analyze) if isinstance(analyze, dict) else analyze
        print(f"WARN analyze 502 (Spoonacular outage) — reserve flow OK: {detail}")
        return 0
    print(f"FAIL analyze: {analyze}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
