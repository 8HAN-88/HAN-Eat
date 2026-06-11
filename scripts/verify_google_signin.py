#!/usr/bin/env python3
"""Проверка готовности Google Sign-In (Flutter + Android + iOS + backend)."""
from __future__ import annotations

import json
import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURES: list[str] = []
WARNINGS: list[str] = []
OK: list[str] = []


def ok(msg: str) -> None:
    OK.append(msg)
    print(f"  OK {msg}")


def warn(msg: str) -> None:
    WARNINGS.append(msg)
    print(f"  WARN {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"  FAIL {msg}")


def load_dotenv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def main() -> int:
    print("== Google Sign-In verify ==\n")

    gs_json = ROOT / "android/app/google-services.json"
    if gs_json.is_file():
        data = json.loads(gs_json.read_text(encoding="utf-8"))
        clients = data.get("client") or []
        pkg_ok = any(
            (c.get("client_info") or {}).get("android_client_info", {}).get("package_name")
            == "com.haneat.app"
            for c in clients
        )
        if pkg_ok:
            ok("google-services.json: package com.haneat.app")
        else:
            fail("google-services.json: нет client для com.haneat.app")
        oauth = []
        for c in clients:
            oauth.extend(c.get("oauth_client") or [])
        if oauth:
            ok(f"google-services.json: oauth_client ({len(oauth)} entries)")
        else:
            fail(
                "google-services.json: oauth_client пуст — включите Google в Firebase, "
                "добавьте SHA-1 (./scripts/android_print_sha1.sh), скачайте json заново"
            )
    else:
        fail("android/app/google-services.json не найден")

    plist_path = ROOT / "ios/Runner/GoogleService-Info.plist"
    if plist_path.is_file():
        with plist_path.open("rb") as f:
            pl = plistlib.load(f)
        if pl.get("BUNDLE_ID") == "com.haneat.app":
            ok("GoogleService-Info.plist: bundle com.haneat.app")
        else:
            warn(f"GoogleService-Info.plist BUNDLE_ID={pl.get('BUNDLE_ID')}")
        rev = pl.get("REVERSED_CLIENT_ID")
        if rev:
            ok(f"REVERSED_CLIENT_ID={rev}")
            info = (ROOT / "ios/Runner/Info.plist").read_text(encoding="utf-8")
            if rev in info:
                ok("Info.plist содержит REVERSED_CLIENT_ID scheme")
            else:
                fail(
                    f"Info.plist без scheme {rev} — запустите: "
                    "python3 scripts/ios_apply_google_url_scheme.py"
                )
        else:
            fail("GoogleService-Info.plist без REVERSED_CLIENT_ID")
    else:
        fail(
            "ios/Runner/GoogleService-Info.plist отсутствует — скачайте из Firebase Console"
        )

    flutter_env = load_dotenv(ROOT / ".env")
    web_id = flutter_env.get("GOOGLE_WEB_CLIENT_ID", "")
    ios_id = flutter_env.get("GOOGLE_IOS_CLIENT_ID", "")
    if web_id and web_id.endswith(".apps.googleusercontent.com"):
        ok("Flutter .env: GOOGLE_WEB_CLIENT_ID")
    else:
        warn("Flutter .env: GOOGLE_WEB_CLIENT_ID не задан (нужен для serverClientId)")
    if ios_id and not plist_path.is_file():
        ok("Flutter .env: GOOGLE_IOS_CLIENT_ID (fallback без plist)")
    elif plist_path.is_file() and not ios_id:
        ok("iOS client из GoogleService-Info.plist")

    backend_env = load_dotenv(ROOT / "backend/.env")
    backend_ids = backend_env.get("GOOGLE_OAUTH_CLIENT_IDS", "")
    if backend_ids:
        ok("backend/.env: GOOGLE_OAUTH_CLIENT_IDS")
    else:
        fail("backend/.env: GOOGLE_OAUTH_CLIENT_IDS пуст")
    if backend_env.get("SKIP_GOOGLE_ID_TOKEN_VERIFICATION", "").lower() in (
        "1",
        "true",
        "yes",
    ):
        warn("SKIP_GOOGLE_ID_TOKEN_VERIFICATION=true (только dev)")

    print("\n== SUMMARY ==")
    print(f"  ok: {len(OK)}  warn: {len(WARNINGS)}  fail: {len(FAILURES)}")
    if FAILURES:
        print("\nСм. docs/GOOGLE_SIGNIN_SETUP.md")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
