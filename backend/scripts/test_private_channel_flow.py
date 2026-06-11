#!/usr/bin/env python3
"""
E2E smoke-тест: приватный канал, заявки, видимость постов, поиск.
Запуск: cd backend && python3 scripts/test_private_channel_flow.py
"""
from __future__ import annotations

import json
import sys
import time
import uuid
from typing import Any, Optional

import httpx

PASSWORD = "HANtest2026!"
CREATOR_EMAIL = "han.test.creator@haneat.dev"
FREE_EMAIL = "han.test.free@haneat.dev"


class TestFailure(Exception):
    pass


def detect_base() -> str:
    for port in (5001, 5000):
        url = f"http://127.0.0.1:{port}/api/v1/auth/login"
        try:
            with httpx.Client(timeout=3.0) as c:
                r = c.post(
                    url,
                    json={"email": CREATOR_EMAIL, "password": PASSWORD},
                )
                if r.status_code == 200 and r.json().get("token"):
                    return f"http://127.0.0.1:{port}/api/v1"
        except httpx.ConnectError:
            continue
    raise TestFailure("API not reachable on ports 5001 or 5000")


def ok(cond: bool, msg: str) -> None:
    if not cond:
        raise TestFailure(msg)


def auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def main() -> int:
    base = detect_base()
    suffix = uuid.uuid4().hex[:8]
    channel_name = f"QA Private {suffix}"
    channel_slug = f"qa_private_{suffix}"

    print("=== Private channel E2E ===")
    print(f"API: {base}\n")

    def login_local(client: httpx.Client, email: str) -> str:
        r = client.post(
            f"{base}/auth/login",
            json={"email": email, "password": PASSWORD},
            timeout=30.0,
        )
        if r.status_code != 200:
            raise TestFailure(f"Login {email}: {r.status_code} {r.text[:300]}")
        token = r.json().get("token")
        ok(bool(token), f"No token for {email}")
        return token

    with httpx.Client() as client:
        print("1. Login creator + free user")
        creator_token = login_local(client, CREATOR_EMAIL)
        free_token = login_local(client, FREE_EMAIL)
        print("   OK\n")

        print("2. Create private channel")
        r = client.post(
            f"{base}/channels",
            headers=auth_headers(creator_token),
            json={
                "name": channel_name,
                "slug": channel_slug,
                "description": "QA private channel",
                "is_public": False,
                "recipe_visibility_mode": "mixed",
            },
            timeout=30.0,
        )
        ok(r.status_code == 201, f"Create channel: {r.status_code} {r.text[:300]}")
        channel_id = r.json()["id"]
        print(f"   channel_id={channel_id}\n")

        print("3. Creator sees channel in subscribed list")
        r = client.get(
            f"{base}/channels",
            params={"subscribed": "true", "limit": 50},
            headers=auth_headers(creator_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Subscribed list: {r.status_code}")
        ids = [c["id"] for c in r.json().get("items", [])]
        ok(channel_id in ids, "Creator channel not in subscribed list")
        print("   OK\n")

        print("4. Search finds private channel (free user)")
        r = client.get(
            f"{base}/channels",
            params={"search": channel_name, "limit": 20},
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Search: {r.status_code}")
        found = next(
            (c for c in r.json().get("items", []) if c["id"] == channel_id),
            None,
        )
        ok(found is not None, "Private channel not found in search")
        ok(found.get("is_public") is False, "Channel should be private")
        ok(
            found.get("membership_status") in ("none", None),
            f"Expected membership none, got {found.get('membership_status')}",
        )
        print("   OK\n")

        print("5. Free user: channel preview, no posts")
        r = client.get(
            f"{base}/channels/{channel_id}",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Get channel: {r.status_code}")
        detail = r.json()
        ok(detail.get("can_view_posts") is False, "can_view_posts should be false")
        ok(
            detail.get("membership_status") == "none",
            f"membership_status={detail.get('membership_status')}",
        )
        r_posts = client.get(
            f"{base}/channels/{channel_id}/posts",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(
            r_posts.status_code == 403,
            f"Posts should be 403, got {r_posts.status_code}",
        )
        print("   OK\n")

        print("6. Free user joins -> pending")
        r = client.post(
            f"{base}/channels/{channel_id}/join",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Join: {r.status_code} {r.text[:200]}")
        join = r.json()
        ok(join.get("pending") is True, f"Expected pending=true, got {join}")
        ok(join.get("joined") is False, "Should not be joined yet")
        ok(
            join.get("membership_status") == "pending",
            f"status={join.get('membership_status')}",
        )
        print("   OK\n")

        print("7. Still cannot view posts while pending")
        r = client.get(
            f"{base}/channels/{channel_id}",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        detail = r.json()
        ok(detail.get("membership_status") == "pending", "Should be pending")
        ok(detail.get("can_view_posts") is False, "Still no posts")
        r_posts = client.get(
            f"{base}/channels/{channel_id}/posts",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r_posts.status_code == 403, f"Posts pending: {r_posts.status_code}")
        print("   OK\n")

        print("8. Not in subscribed until approved")
        r = client.get(
            f"{base}/channels",
            params={"subscribed": "true", "limit": 50},
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ids = [c["id"] for c in r.json().get("items", [])]
        ok(channel_id not in ids, "Pending channel must not be in subscribed")
        print("   OK\n")

        print("9. Creator sees join request")
        r = client.get(
            f"{base}/channels/{channel_id}",
            headers=auth_headers(creator_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, "Creator get channel")
        pending_count = r.json().get("pending_join_requests_count")
        ok(
            pending_count is not None and pending_count >= 1,
            f"pending_join_requests_count={pending_count}",
        )
        r = client.get(
            f"{base}/channels/{channel_id}/join-requests",
            headers=auth_headers(creator_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Join requests: {r.status_code}")
        items = r.json().get("items", [])
        ok(len(items) >= 1, "No join requests")
        free_user_id = items[0]["user_id"]
        print(f"   free_user_id={free_user_id}\n")

        print("10. Approve join request")
        r = client.post(
            f"{base}/channels/{channel_id}/join-requests/{free_user_id}/approve",
            headers=auth_headers(creator_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Approve: {r.status_code} {r.text[:200]}")
        ok(r.json().get("joined") is True, "Should be joined after approve")
        print("   OK\n")

        print("11. Free user: active member, can view posts")
        r = client.get(
            f"{base}/channels/{channel_id}",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        detail = r.json()
        ok(detail.get("is_member") is True, "Should be member")
        ok(detail.get("can_view_posts") is True, "Should view posts")
        ok(
            detail.get("membership_status") == "active",
            f"status={detail.get('membership_status')}",
        )
        r_posts = client.get(
            f"{base}/channels/{channel_id}/posts",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r_posts.status_code == 200, f"Posts after approve: {r_posts.status_code}")
        print("   OK\n")

        print("12. Channel in subscribed list after approval")
        r = client.get(
            f"{base}/channels",
            params={"subscribed": "true", "limit": 50},
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ids = [c["id"] for c in r.json().get("items", [])]
        ok(channel_id in ids, "Channel should appear in subscribed")
        print("   OK\n")

        print("13. Cleanup: free leaves, creator deletes channel")
        r = client.delete(
            f"{base}/channels/{channel_id}/join",
            headers=auth_headers(free_token),
            timeout=30.0,
        )
        ok(r.status_code == 200, f"Leave: {r.status_code}")

        # Delete may require owner only - try
        r = client.delete(
            f"{base}/channels/{channel_id}",
            headers=auth_headers(creator_token),
            timeout=30.0,
        )
        if r.status_code not in (200, 204):
            print(f"   WARN: delete channel {r.status_code} (manual cleanup slug={channel_slug})")
        else:
            print("   Channel deleted")
        print()

    print("=== ALL TESTS PASSED ===\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except TestFailure as e:
        print(f"\nFAIL: {e}\n")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}\n")
        sys.exit(2)
