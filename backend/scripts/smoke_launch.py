#!/usr/bin/env python3
"""
Smoke перед релизом: health, readiness, auth, feed, post, payments, meal plan.

  BASE_URL=http://127.0.0.1:5001 python3 backend/scripts/smoke_launch.py
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:5001").rstrip("/")
API = f"{BASE}/api/v1"
FAILURES: list[str] = []
PASSED: list[str] = []
_last_refresh_token: str | None = None


def ok(msg: str) -> None:
    PASSED.append(msg)
    print(f"  OK {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"  FAIL {msg}")


def section(title: str) -> None:
    print(f"\n== {title} ==")


def req(method: str, path: str, headers: dict | None = None, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    hdrs = {"Content-Type": "application/json", **(headers or {})}
    url = path if path.startswith("http") else f"{API}{path}"
    r = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(r, timeout=45) as resp:
            raw = resp.read().decode("utf-8")
            if not raw:
                return resp.status, {}
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, {"_raw": raw}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"_raw": raw}
        return e.code, payload


def login_or_register() -> dict[str, str]:
    global _last_refresh_token
    email = os.environ.get("SMOKE_EMAIL", f"launch{time.time_ns()}@example.com")
    password = os.environ.get("SMOKE_PASSWORD", "password123")
    code, data = req("POST", "/auth/login", body={"email": email, "password": password})
    if code == 200 and data.get("token"):
        _last_refresh_token = data.get("refresh_token")
        return {"Authorization": f"Bearer {data['token']}"}
    code, reg = req(
        "POST",
        "/auth/register",
        body={
            "email": email,
            "password": password,
            "name": "Launch Smoke",
            "username": email.split("@")[0][:28],
        },
    )
    if code in (200, 201) and reg.get("token"):
        _last_refresh_token = reg.get("refresh_token")
        return {"Authorization": f"Bearer {reg['token']}"}
    raise RuntimeError(f"auth failed login={code} register={reg}")


def test_public() -> None:
    section("public")
    c, _ = req("GET", f"{BASE}/health")
    if c == 200:
        ok("health")
    else:
        fail(f"health HTTP {c}")

    c, ready = req("GET", "/system/readiness")
    if c == 200 and "issues" in ready:
        ok("system/readiness")
        if ready.get("issues"):
            print(f"  WARN readiness issues: {ready['issues']}")
    elif c == 404:
        c2, pay = req("GET", "/payments/readiness")
        if c2 == 200:
            ok("payments/readiness (перезапустите API для /system/readiness)")
        else:
            fail(f"system/readiness 404, payments/readiness HTTP {c2}")
    else:
        fail(f"system/readiness HTTP {c}")

    c, _ = req("GET", "/ai-scan/limits")
    if c == 200:
        ok("ai-scan/limits")
    else:
        fail(f"ai-scan/limits HTTP {c}")

    c, prices = req("GET", "/payments/prices?country=RU")
    if c == 200 and isinstance(prices, dict):
        ok("payments/prices")
    else:
        fail(f"payments/prices HTTP {c}")

    c, ch = req("GET", "/channels?catalog=true&limit=1")
    if c == 200 and ("items" in ch or "channels" in ch):
        ok("channels catalog (guest)")
    else:
        fail(f"channels HTTP {c} {list(ch.keys()) if isinstance(ch, dict) else ch}")

    c, privacy = req("GET", f"{BASE}/privacy")
    if c == 200 and (
        isinstance(privacy.get("_raw"), str) and "html" in privacy["_raw"].lower()
    ):
        ok("legal /privacy")
    else:
        fail(f"legal /privacy HTTP {c}")


def test_auth_feed_post(auth: dict) -> None:
    section("auth + feed + post")
    c, me = req("GET", "/users/me", auth)
    if c == 200 and me.get("id"):
        ok("users/me")
    else:
        fail(f"users/me HTTP {c}")
        return

    c, feed = req("GET", "/feed?limit=5", auth)
    if c == 200 and "items" in feed:
        ok("feed")
    else:
        fail(f"feed HTTP {c}")

    c, post = req(
        "POST",
        "/posts",
        auth,
        {
            "type": "text",
            "title": "Launch smoke",
            "description": "Automated pre-launch check",
            "visibility": "public",
            "publish_to": ["feed"],
        },
    )
    if c in (200, 201) and post.get("id"):
        ok(f"post created id={post['id']}")
    else:
        fail(f"create post HTTP {c} {post}")


def test_payments_meal_plan(auth: dict) -> None:
    section("payments + meal plan")
    c, pay = req("GET", "/payments/readiness")
    if c == 200:
        ok("payments/readiness")
    else:
        fail(f"payments/readiness HTTP {c}")

    c, hist = req("GET", "/payments/history", auth)
    if c == 200:
        ok("payments/history")
    else:
        fail(f"payments/history HTTP {c}")

    c, limits = req("GET", "/meal-plans/limits", auth)
    if c == 200 and "tier" in limits:
        ok("meal-plans/limits")
    else:
        fail(f"meal-plans/limits HTTP {c} {limits}")


def test_subscriptions(auth: dict) -> None:
    section("subscriptions")
    c, status = req("GET", "/subscriptions/status", auth)
    if c == 200 and "entitlements" in status:
        ok("subscriptions/status")
    else:
        fail(f"subscriptions/status HTTP {c} {status}")

    if not _last_refresh_token:
        fail("auth/refresh: no refresh_token from login")
        return

    c, refresh = req(
        "POST",
        "/auth/refresh",
        auth,
        {"refresh_token": _last_refresh_token},
    )
    if c == 200 and refresh.get("token"):
        ok("auth/refresh")
    else:
        fail(f"auth/refresh HTTP {c} {refresh}")


def main() -> int:
    print(f"BASE_URL={BASE}")
    try:
        test_public()
        auth = login_or_register()
        print(f"  user token OK")
        test_auth_feed_post(auth)
        test_payments_meal_plan(auth)
        test_subscriptions(auth)
    except Exception as e:
        fail(str(e))

    section("SUMMARY")
    print(f"  passed: {len(PASSED)}")
    print(f"  failed: {len(FAILURES)}")
    if FAILURES:
        for f in FAILURES:
            print(f"    - {f}")
        return 1
    print("  LAUNCH SMOKE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
