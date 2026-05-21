#!/usr/bin/env python3
"""
Полный smoke по ТЗ: подписки/ЮKassa + Creator V2.
Usage:
  SMOKE_PASSWORD=secret [SMOKE_EMAIL=...] [ADMIN_EMAIL=...] [ADMIN_PASSWORD=...] \\
    python3 backend/scripts/smoke_tz_full.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:5001").rstrip("/")
API = f"{BASE}/api/v1"
FAILURES: list[str] = []
PASSED: list[str] = []


def ok(msg: str) -> None:
    PASSED.append(msg)
    print(f"  OK {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"  FAIL {msg}")


def req(method: str, path: str, headers: dict | None = None, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    hdrs = {"Content-Type": "application/json", **(headers or {})}
    url = path if path.startswith("http") else f"{API}{path}"
    r = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(r, timeout=45) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return e.code, payload


def login_or_register() -> tuple[dict[str, str], str]:
    email = os.environ.get("SMOKE_EMAIL", f"smoke{__import__('time').time_ns()}@example.com")
    password = os.environ.get("SMOKE_PASSWORD", "password123")
    code, data = req("POST", "/auth/login", body={"email": email, "password": password})
    if code == 200 and data.get("token"):
        return {"Authorization": f"Bearer {data['token']}"}, email
    if os.environ.get("SMOKE_AUTO_REGISTER", "1").lower() in ("1", "true", "yes"):
        code, reg = req(
            "POST",
            "/auth/register",
            body={
                "email": email,
                "password": password,
                "name": "TZ Smoke",
                "username": email.split("@")[0][:28],
            },
        )
        if code in (200, 201) and reg.get("token"):
            return {"Authorization": f"Bearer {reg['token']}"}, email
    raise RuntimeError(f"login failed {code} {data}")


def section(title: str) -> None:
    print(f"\n== {title} ==")


def run_existing_scripts(email: str) -> None:
    root = os.path.dirname(os.path.abspath(__file__))
    env = {
        **os.environ,
        "BASE_URL": BASE,
        "SMOKE_AUTO_REGISTER": "1",
        "SMOKE_EMAIL": email,
        "SMOKE_PASSWORD": os.environ.get("SMOKE_PASSWORD", "password123"),
    }
    scripts = [
        ("smoke_public_api.sh", ["bash", f"{root}/smoke_public_api.sh", BASE]),
        ("smoke_subscriptions.py", [sys.executable, f"{root}/smoke_subscriptions.py"]),
    ]
    if env.get("ADMIN_EMAIL") and env.get("ADMIN_PASSWORD"):
        scripts.append(("smoke_admin_refunds.py", [sys.executable, f"{root}/smoke_admin_refunds.py"]))
    scripts.append(("smoke_ai_scan_auth.py", [sys.executable, f"{root}/smoke_ai_scan_auth.py"]))

    for name, cmd in scripts:
        section(f"script {name}")
        r = subprocess.run(cmd, env=env, cwd=os.path.dirname(root), capture_output=True, text=True)
        print(r.stdout[-2000:] if len(r.stdout) > 2000 else r.stdout)
        if r.stderr:
            print(r.stderr[-500:])
        if r.returncode == 0:
            ok(name)
        else:
            fail(f"{name} exit={r.returncode}")


def test_subscriptions_tz(auth: dict) -> None:
    section("ТЗ1: subscriptions/status + entitlements")
    c, st = req("GET", "/subscriptions/status", auth)
    if c != 200:
        fail(f"status HTTP {c}")
        return
    ok("subscriptions/status 200")
    for k in ("subscription_type", "is_active", "has_ai", "has_creator", "upgrade_options"):
        if k not in st:
            fail(f"status missing {k}")
        else:
            ok(f"status.{k}")
    opts = st.get("upgrade_options") or []
    if opts and "amount_due" not in opts[0]:
        fail("upgrade_options without proration fields")
    else:
        ok("upgrade_options proration fields")

    section("ТЗ1: trial pro (Creator+AI)")
    c, trial = req("POST", "/subscriptions/trial", auth, {"product": "pro"})
    if c == 200:
        ok("trial pro started")
    elif c == 400:
        ok(f"trial pro skipped ({trial.get('detail', trial)})")
    else:
        fail(f"trial pro HTTP {c}")

    c, st2 = req("GET", "/subscriptions/status", auth)
    if c == 200 and st2.get("has_creator"):
        ok("has_creator after trial pro")
    elif c == 200:
        fail(f"expected has_creator, got {st2.get('subscription_type')}")

    section("ТЗ1: payments")
    c, ready = req("GET", "/payments/readiness")
    if c == 200 and "webhook_url" in ready:
        ok("payments/readiness")
    else:
        fail(f"readiness HTTP {c}")
    c, hist = req("GET", "/payments/history", auth)
    if c == 200 and "payments" in hist:
        ok("payments/history")
    else:
        fail(f"history HTTP {c}")


def test_creator_tz(auth: dict) -> None:
    section("ТЗ2: creator/stats")
    c, stats = req("GET", "/creator/stats", auth)
    if c != 200:
        fail(f"creator/stats HTTP {c}")
        return
    for k in ("has_creator", "promoted_count", "promoted_limit", "scheduled_count"):
        if k not in stats:
            fail(f"stats missing {k}")
    ok("creator/stats fields")
    if not stats.get("has_creator"):
        fail("has_creator=false after trial pro")
    else:
        ok("has_creator=true")

    section("ТЗ2: creator/posts/promoted + scheduled")
    c, prom = req("GET", "/creator/posts/promoted", auth)
    if c == 200 and "posts" in prom:
        ok("creator/posts/promoted")
    else:
        fail(f"promoted HTTP {c} {prom}")
    c, sched = req("GET", "/creator/posts/scheduled", auth)
    if c == 200 and "posts" in sched:
        ok("creator/posts/scheduled")
    else:
        fail(f"scheduled HTTP {c} {sched}")

    section("ТЗ2: analytics (Creator gate)")
    c, an = req("GET", "/analytics/profile", auth)
    if c == 200:
        ok("analytics/profile (creator allowed)")
    elif c == 403:
        fail("analytics 403 despite creator")
    else:
        fail(f"analytics HTTP {c}")


def test_admin_refund_acl() -> None:
    section("ТЗ1: admin refund ACL")
    admin_email = os.environ.get("ADMIN_EMAIL")
    admin_pass = os.environ.get("ADMIN_PASSWORD")
    if not admin_pass:
        print("  SKIP (no ADMIN_PASSWORD)")
        return
    user_email = f"acl{__import__('time').time_ns()}@example.com"
    code, reg = req(
        "POST",
        "/auth/register",
        body={
            "email": user_email,
            "password": "password123",
            "name": "ACL",
            "username": f"acl{__import__('time').time_ns() % 100000}"[:28],
        },
    )
    token = reg.get("token") if code in (200, 201) else None
    if not token:
        fail(f"acl user register HTTP {code}")
        return
    user_auth = {"Authorization": f"Bearer {token}"}
    c, _ = req("GET", "/payments/admin/refund-queue", user_auth)
    if c == 403:
        ok("non-admin denied refund-queue")
    else:
        fail(f"expected 403 for user, got {c}")

    if admin_email:
        c, login = req("POST", "/auth/login", body={"email": admin_email, "password": admin_pass})
        if c == 200:
            admin_auth = {"Authorization": f"Bearer {login['token']}"}
            c2, q = req("GET", "/payments/admin/refund-queue", admin_auth)
            if c2 == 200:
                ok("admin refund-queue")
            else:
                fail(f"admin queue HTTP {c2}")


def main() -> int:
    print(f"BASE_URL={BASE}")
    try:
        c, h = req("GET", f"{BASE}/health")
        if c != 200:
            fail(f"health HTTP {c}")
            print("\nStart backend: cd backend && uvicorn app.main:app --port 5001")
            return 1
        ok("health")
    except Exception as e:
        fail(f"health unreachable: {e}")
        return 1

    try:
        auth, email = login_or_register()
        print(f"  user: {email}")
        os.environ["SMOKE_EMAIL"] = email
        run_existing_scripts(email)
        test_subscriptions_tz(auth)
        test_creator_tz(auth)
        test_admin_refund_acl()
    except Exception as e:
        fail(f"auth flow: {e}")

    section("SUMMARY")
    print(f"  passed: {len(PASSED)}")
    print(f"  failed: {len(FAILURES)}")
    if FAILURES:
        for f in FAILURES:
            print(f"    - {f}")
        return 1
    print("  ALL TZ SMOKE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
