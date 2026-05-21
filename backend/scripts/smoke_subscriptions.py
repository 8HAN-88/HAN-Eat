#!/usr/bin/env python3
"""
E2E smoke: login → subscription status (proration) → prices → payment history → creator stats.
Usage:
  SMOKE_EMAIL=user@example.com SMOKE_PASSWORD=secret \\
    python3 backend/scripts/smoke_subscriptions.py
  BASE_URL=http://127.0.0.1:5001 python3 ...
Optional:
  SMOKE_AUTO_REGISTER=1  — register if login fails
  SMOKE_TRIAL=1          — try POST /subscriptions/trial (ai), warn on failure
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


def _login(api: str) -> dict[str, str] | None:
    email = os.environ.get("SMOKE_EMAIL", "").strip()
    password = os.environ.get("SMOKE_PASSWORD", "").strip()
    if not email or not password:
        print("SKIP: set SMOKE_EMAIL and SMOKE_PASSWORD")
        return None

    print(f"== login ({email}) ==")
    code, data = _request(
        "POST",
        f"{api}/auth/login",
        body={"email": email, "password": password},
    )
    if code == 200 and data.get("token"):
        return {"Authorization": f"Bearer {data['token']}"}

    if os.environ.get("SMOKE_AUTO_REGISTER", "").lower() not in ("1", "true", "yes"):
        print(f"FAIL login HTTP {code}: {data}")
        return None

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
    if code not in (200, 201) or not reg.get("token"):
        print(f"FAIL register HTTP {code}: {reg}")
        return None
    return {"Authorization": f"Bearer {reg['token']}"}


def _check_upgrade_options(status: dict) -> bool:
    opts = status.get("upgrade_options")
    if opts is None:
        print(
            "FAIL: upgrade_options missing — перезапустите backend "
            "(нужен актуальный subscription_service.get_status_dict)"
        )
        return False
    if not isinstance(opts, list):
        print(f"FAIL: upgrade_options not a list: {type(opts)}")
        return False
    for opt in opts:
        for key in ("product", "monthly_price", "amount_due", "full_price"):
            if key not in opt:
                print(f"FAIL: upgrade option missing {key!r}: {opt}")
                return False
        due = float(opt.get("amount_due", 0))
        full = float(opt.get("full_price", 0))
        if due > full + 0.01:
            print(f"FAIL: amount_due > full_price: {opt}")
            return False
        if opt.get("is_upgrade") and float(opt.get("credit_rub", 0)) < 0:
            print(f"FAIL: negative credit_rub: {opt}")
            return False
    print(f"OK upgrade_options ({len(opts)} items)")
    return True


def _check_payment_history_fields(payments: list) -> bool:
    if not payments:
        print("OK payment history (empty)")
        return True
    p0 = payments[0]
    for key in ("id", "amount", "refund_status", "can_request_refund"):
        if key not in p0:
            print(f"FAIL: payment history item missing {key!r}: {p0}")
            return False
    print(f"OK payment history fields ({len(payments)} items)")
    return True


def main() -> int:
    base = os.environ.get("BASE_URL", "http://127.0.0.1:5001").rstrip("/")
    api = f"{base}/api/v1"

    auth = _login(api)
    if auth is None:
        return 0 if not os.environ.get("SMOKE_PASSWORD") else 1

    print("== subscriptions/status ==")
    code, status = _request("GET", f"{api}/subscriptions/status", headers=auth)
    print(f"HTTP {code}", {k: status.get(k) for k in ("subscription_type", "is_active", "in_grace_period")})
    if code != 200:
        return 1
    if not _check_upgrade_options(status):
        return 1

    print("== payments/readiness ==")
    code, ready = _request("GET", f"{api}/payments/readiness")
    print(
        f"HTTP {code} ready={ready.get('ready')} issues={ready.get('issues')}"
        if code == 200
        else ready
    )
    if code != 200:
        return 1

    print("== payments/prices ==")
    code, prices = _request("GET", f"{api}/payments/prices", headers=auth)
    tiers = prices.get("tiers") if isinstance(prices, dict) else None
    print(f"HTTP {code} provider={prices.get('provider')!r} tiers={list(tiers.keys()) if tiers else None}")
    if code != 200:
        return 1
    if not tiers or not all(t in tiers for t in ("ai", "creator", "pro")):
        print(f"FAIL: expected ai/creator/pro tiers in prices: {prices}")
        return 1

    print("== payments/history ==")
    code, history = _request("GET", f"{api}/payments/history", headers=auth)
    if code == 404:
        print("FAIL: GET /payments/history → 404 (перезапустите backend: uvicorn app.main:app)")
        return 1
    items = []
    if isinstance(history, list):
        items = history
    elif isinstance(history, dict):
        items = history.get("payments") or history.get("items") or []
    print(f"HTTP {code} items={len(items)}")
    if code != 200:
        return 1
    if not _check_payment_history_fields(items):
        return 1

    print("== creator/stats ==")
    code, stats = _request("GET", f"{api}/creator/stats", headers=auth)
    print(f"HTTP {code}", stats)
    if code != 200:
        return 1
    if "has_creator" not in stats:
        print(f"FAIL: creator/stats missing has_creator: {stats}")
        return 1

    print("== creator/posts/promoted ==")
    code, promoted = _request("GET", f"{api}/creator/posts/promoted", headers=auth)
    if code == 403:
        print("OK creator/posts/promoted → 403 (no Creator tier)")
    elif code == 200:
        posts = promoted.get("posts") if isinstance(promoted, dict) else None
        print(f"OK creator/posts/promoted posts={len(posts) if posts is not None else promoted}")
    else:
        print(f"FAIL creator/posts/promoted HTTP {code}: {promoted}")
        return 1

    if os.environ.get("SMOKE_TRIAL", "").lower() in ("1", "true", "yes"):
        print("== subscriptions/trial (ai) ==")
        code, trial = _request(
            "POST",
            f"{api}/subscriptions/trial",
            headers=auth,
            body={"product": "ai"},
        )
        if code == 200:
            print("OK trial started", trial)
        else:
            print(f"WARN trial HTTP {code}: {trial}")

    print("OK subscription smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
