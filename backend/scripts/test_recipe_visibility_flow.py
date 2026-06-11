#!/usr/bin/env python3
"""Smoke: приватный рецепт — is_global_visible=false, не в Menu-поиске."""
from __future__ import annotations

import sys
import uuid

import httpx

PASSWORD = "HANtest2026!"
CREATOR_EMAIL = "han.test.creator@haneat.dev"


class TestFailure(Exception):
    pass


def ok(cond: bool, msg: str) -> None:
    if not cond:
        raise TestFailure(msg)


def detect_base() -> str:
    for port in (5001, 5000):
        try:
            with httpx.Client(timeout=5.0) as c:
                r = c.post(
                    f"http://127.0.0.1:{port}/api/v1/auth/login",
                    json={"email": CREATOR_EMAIL, "password": PASSWORD},
                )
                if r.status_code == 200 and r.json().get("token"):
                    return f"http://127.0.0.1:{port}/api/v1"
        except httpx.ConnectError:
            continue
    raise TestFailure("API not reachable")


def main() -> int:
    base = detect_base()
    suffix = uuid.uuid4().hex[:8]
    marker = f"uniqvis{suffix}"

    print(f"=== Recipe visibility E2E ({base}) ===\n")
    with httpx.Client(timeout=60.0) as client:
        token = client.post(
            f"{base}/auth/login",
            json={"email": CREATOR_EMAIL, "password": PASSWORD},
        ).json()["token"]
        h = {"Authorization": f"Bearer {token}"}

        ch = client.post(
            f"{base}/channels",
            headers=h,
            json={
                "name": f"QA Vis {suffix}",
                "slug": f"qa_vis_{suffix}",
                "is_public": True,
                "recipe_visibility_mode": "mixed",
            },
        )
        ok(ch.status_code == 201, f"channel: {ch.status_code}")
        channel_id = ch.json()["id"]

        priv = client.post(
            f"{base}/channels/{channel_id}/recipe",
            headers=h,
            json={
                "type": "recipe",
                "title": f"Private {marker}",
                "description": marker,
                "visibility": "private",
                "body": {
                    "ingredients": [marker, "egg"],
                    "steps": ["mix"],
                    "calories": 100,
                },
            },
        )
        ok(priv.status_code == 201, f"private recipe: {priv.status_code} {priv.text[:300]}")
        priv_body = priv.json()
        priv_id = priv_body["id"]
        ok(
            priv_body.get("visibility") == "private",
            f"visibility={priv_body.get('visibility')}",
        )
        ok(
            priv_body.get("is_global_visible") is False,
            f"private is_global_visible={priv_body.get('is_global_visible')}",
        )

        pub = client.post(
            f"{base}/channels/{channel_id}/recipe",
            headers=h,
            json={
                "type": "recipe",
                "title": f"Public {marker}",
                "description": marker,
                "visibility": "public",
                "body": {
                    "ingredients": [marker, "flour"],
                    "steps": ["bake"],
                    "calories": 200,
                },
            },
        )
        ok(pub.status_code == 201, f"public recipe: {pub.status_code}")
        pub_body = pub.json()
        pub_id = pub_body["id"]
        ok(
            pub_body.get("visibility") == "public",
            f"visibility={pub_body.get('visibility')}",
        )
        if pub_body.get("status") == "published":
            ok(
                pub_body.get("is_global_visible") is True,
                f"public is_global_visible={pub_body.get('is_global_visible')}",
            )
            menu = client.post(
                f"{base}/recipes",
                json={"ingredients": marker, "language": "ru"},
            )
            ok(menu.status_code == 200, f"menu search: {menu.status_code}")
            recipes = menu.json().get("recipes") or []
            menu_ids = {r.get("id") for r in recipes if isinstance(r, dict)}
            ok(
                not any(str(priv_id) == str(mid) for mid in menu_ids),
                f"Private recipe leaked to menu: {menu_ids}",
            )
        else:
            print(
                f"   WARN: public recipe status={pub_body.get('status')} "
                "(moderation pending — menu index skipped)"
            )

        if priv_body.get("status") == "published":
            ch_posts = client.get(f"{base}/channels/{channel_id}/posts", headers=h)
            ok(ch_posts.status_code == 200, "channel posts")
            ch_ids = {p["id"] for p in ch_posts.json().get("posts", [])}
            ok(priv_id in ch_ids, "Private visible inside channel")
            ok(pub_id in ch_ids, "Public visible inside channel")
        else:
            print(
                "   WARN: recipes pending moderation — channel feed check skipped"
            )

        client.delete(f"{base}/channels/{channel_id}", headers=h)
        print("\n=== RECIPE VISIBILITY TESTS PASSED ===\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except TestFailure as e:
        print(f"\nFAIL: {e}\n")
        sys.exit(1)
