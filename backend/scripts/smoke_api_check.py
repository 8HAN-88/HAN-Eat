#!/usr/bin/env python3
"""
Быстрая проверка API после деплоя (health + публичные эндпоинты).
Использование:
  python3 scripts/smoke_api_check.py
  python3 scripts/smoke_api_check.py --base https://api.haneat.app
  API_BASE=https://api.haneat.app python3 scripts/smoke_api_check.py --login creator@test.haneat.app
"""
from __future__ import annotations

import argparse
import os
import sys

import httpx

DEFAULT_BASE = os.environ.get("API_BASE", "http://127.0.0.1:5000").rstrip("/")
DEFAULT_PASSWORD = os.environ.get("SMOKE_PASSWORD", "HANtest2026!")
DEFAULT_LOGIN = os.environ.get("SMOKE_EMAIL", "han.test.creator@haneat.dev")


def ok(msg: str) -> None:
    print(f"  OK  {msg}")


def fail(msg: str) -> None:
    print(f"  FAIL {msg}", file=sys.stderr)


def warn(msg: str) -> None:
    print(f"  WARN {msg}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke-check HAN Eat API")
    parser.add_argument("--base", default=DEFAULT_BASE, help="API base URL")
    parser.add_argument(
        "--login",
        default=DEFAULT_LOGIN,
        help="Email for authenticated checks (default: creator test account)",
    )
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    args = parser.parse_args()
    base = args.base.rstrip("/")
    api = f"{base}/api/v1"
    errors = 0

    print(f"Smoke API: {base}\n")

    with httpx.Client(timeout=15.0) as client:
        try:
            r = client.get(f"{base}/health")
            if r.status_code == 200:
                ok(f"GET /health -> {r.status_code}")
            else:
                fail(f"GET /health -> {r.status_code}")
                errors += 1
        except httpx.RequestError as e:
            fail(f"GET /health unreachable: {e}")
            return 1

        try:
            r = client.get(f"{api}/feed", params={"limit": 3})
            if r.status_code in (200, 401, 403):
                ok(f"GET /feed -> {r.status_code}")
            else:
                fail(f"GET /feed -> {r.status_code}")
                errors += 1
        except httpx.RequestError as e:
            fail(f"GET /feed: {e}")
            errors += 1

        token = None
        refresh_token = None
        if args.login:
            try:
                r = client.post(
                    f"{api}/auth/login",
                    json={"email": args.login, "password": args.password},
                )
                if r.status_code == 200:
                    data = r.json()
                    token = data.get("token") or data.get("access_token")
                    refresh_token = data.get("refresh_token")
                    ok(f"POST /auth/login ({args.login})")
                else:
                    fail(f"POST /auth/login -> {r.status_code} {r.text[:200]}")
                    errors += 1
            except httpx.RequestError as e:
                fail(f"POST /auth/login: {e}")
                errors += 1

        if refresh_token:
            try:
                r = client.post(
                    f"{api}/auth/refresh",
                    json={"refresh_token": refresh_token},
                )
                if r.status_code == 200 and (r.json().get("token") or r.json().get("access_token")):
                    ok("POST /auth/refresh")
                    token = r.json().get("token") or r.json().get("access_token") or token
                else:
                    fail(f"POST /auth/refresh -> {r.status_code}")
                    errors += 1
            except httpx.RequestError as e:
                fail(f"POST /auth/refresh: {e}")
                errors += 1

        if token:
            headers = {"Authorization": f"Bearer {token}"}
            for label, path, params in (
                ("GET /feed (auth)", f"{api}/feed", {"limit": 2}),
                ("GET /channels?mine (auth)", f"{api}/channels", {"limit": 5, "mine": "true"}),
                ("GET /channels?subscribed (auth)", f"{api}/channels", {"limit": 5, "subscribed": "true"}),
            ):
                try:
                    r = client.get(path, params=params, headers=headers)
                    if r.status_code == 200:
                        ok(f"{label} -> {r.status_code}")
                    else:
                        fail(f"{label} -> {r.status_code}")
                        errors += 1
                except httpx.RequestError as e:
                    fail(f"{label}: {e}")
                    errors += 1

            try:
                r = client.post(
                    f"{api}/posts/link/preview",
                    headers=headers,
                    json={"url": "https://example.com"},
                )
                if r.status_code == 200:
                    ok("POST /posts/link/preview (auth)")
                elif r.status_code == 404:
                    warn(
                        "POST /posts/link/preview -> 404 "
                        "(на сервере старая версия API — сделайте git pull + restart)"
                    )
                else:
                    fail(f"POST /posts/link/preview -> {r.status_code}")
                    errors += 1
            except httpx.RequestError as e:
                fail(f"POST /posts/link/preview: {e}")
                errors += 1

            # Жизненный цикл поста профиля: создать → прочитать → удалить
            created_id = None
            try:
                r = client.post(
                    f"{api}/posts",
                    headers=headers,
                    json={
                        "type": "text",
                        "description": "Smoke test post (auto-delete)",
                    },
                )
                if r.status_code == 201:
                    created_id = r.json().get("id")
                    ok(f"POST /posts (text) -> id={created_id}")
                else:
                    fail(f"POST /posts -> {r.status_code} {r.text[:160]}")
                    errors += 1
            except httpx.RequestError as e:
                fail(f"POST /posts: {e}")
                errors += 1

            if created_id:
                try:
                    r = client.get(f"{api}/posts/{created_id}", headers=headers)
                    if r.status_code == 200:
                        ok(f"GET /posts/{created_id}")
                    else:
                        fail(f"GET /posts/{created_id} -> {r.status_code}")
                        errors += 1
                except httpx.RequestError as e:
                    fail(f"GET /posts/{{id}}: {e}")
                    errors += 1

                try:
                    r = client.delete(f"{api}/posts/{created_id}", headers=headers)
                    if r.status_code in (200, 204):
                        ok(f"DELETE /posts/{created_id}")
                    elif r.status_code == 405:
                        warn(
                            f"DELETE /posts/{created_id} -> 405 "
                            "(на сервере старая версия API — сделайте git pull + restart; "
                            f"удалите тестовый пост id={created_id} вручную)"
                        )
                    else:
                        fail(f"DELETE /posts/{created_id} -> {r.status_code}")
                        errors += 1
                except httpx.RequestError as e:
                    fail(f"DELETE /posts/{{id}}: {e}")
                    errors += 1

    print()
    if errors:
        print(f"Finished with {errors} error(s).")
        return 1
    print("All smoke checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
