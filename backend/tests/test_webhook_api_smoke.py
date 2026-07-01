"""Smoke tests for webhook API endpoints."""

import pytest
from fastapi import HTTPException

from app.api.v1 import bots as bots_api
from app.api.v1 import moderation as moderation_api


class _Db:
    def __init__(self):
        self.commits = 0

    def commit(self):
        self.commits += 1


class _User:
    def __init__(self, user_id: int):
        self.id = user_id


class _Bot:
    def __init__(self):
        self.id = 77
        self.bot_username = "demo_bot"
        self.bot_webhook_enabled = True
        self.bot_webhook_url = "https://example.com/hook"
        self.bot_webhook_last_error = None
        self.bot_webhook_last_ok_at = None


@pytest.mark.asyncio
async def test_bot_webhook_test_endpoint_delivers(monkeypatch):
    db = _Db()
    current_user = _User(5)
    bot = _Bot()
    captured = {}

    def _fake_bot_or_404(_db, _bot_id, _owner_id):
        return bot

    def _fake_deliver(db_obj, *, bot_user, update_type, payload, delivery_id=None):
        captured["db"] = db_obj
        captured["bot_user"] = bot_user
        captured["update_type"] = update_type
        captured["payload"] = payload
        captured["delivery_id"] = delivery_id
        return True

    monkeypatch.setattr(bots_api, "_bot_or_404", _fake_bot_or_404)
    monkeypatch.setattr(bots_api, "deliver_webhook_update", _fake_deliver)

    result = await bots_api.test_webhook_delivery(
        bot_id=bot.id,
        current_user=current_user,
        db=db,
    )

    assert result["status"] == "ok"
    assert result["delivered"] is True
    assert captured["update_type"] == "webhook.test"
    assert captured["payload"]["source"] == "manual_test"
    assert isinstance(captured["delivery_id"], str)
    assert len(captured["delivery_id"]) > 8
    assert db.commits == 1


@pytest.mark.asyncio
async def test_bot_webhook_test_endpoint_requires_configured_webhook(monkeypatch):
    db = _Db()
    current_user = _User(5)
    bot = _Bot()
    bot.bot_webhook_enabled = False

    monkeypatch.setattr(bots_api, "_bot_or_404", lambda *_args, **_kwargs: bot)

    with pytest.raises(HTTPException) as exc:
        await bots_api.test_webhook_delivery(
            bot_id=bot.id,
            current_user=current_user,
            db=db,
        )

    assert exc.value.status_code == 400
    assert "Webhook is not configured" in str(exc.value.detail)


@pytest.mark.asyncio
async def test_recovery_playbook_endpoint_runs_actions_and_commits(monkeypatch):
    db = _Db()
    current_user = _User(1)
    called = {}

    monkeypatch.setattr(
        moderation_api,
        "requeue_dead_letters",
        lambda *, limit: called.setdefault("requeue", limit) or 4,
    )
    monkeypatch.setattr(
        moderation_api,
        "force_promote_delayed",
        lambda *, limit: called.setdefault("promote", limit) or 6,
    )
    monkeypatch.setattr(
        moderation_api,
        "webhook_queue_stats",
        lambda: {"queue_depth": 3, "dropped_total": 0},
    )

    audit = {}

    def _fake_log(_db, *, current_user, action, metadata=None):
        audit["user_id"] = current_user.id
        audit["action"] = action
        audit["metadata"] = metadata or {}

    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", _fake_log)

    payload = moderation_api.WebhookRecoveryPlaybookRequest(
        requeue_dead_limit=250,
        promote_delayed_limit=400,
    )
    result = await moderation_api.run_webhooks_recovery_playbook(
        body=payload,
        current_user=current_user,
        db=db,
    )

    assert called["requeue"] == 250
    assert called["promote"] == 400
    assert result["status"] == "ok"
    assert result["requeued_dead_letters"] == 250
    assert result["promoted_delayed"] == 400
    assert result["stats"]["queue_depth"] == 3
    assert audit["action"] == "bot_webhook_recovery_playbook_run"
    assert audit["user_id"] == 1
    assert db.commits == 1


@pytest.mark.asyncio
async def test_list_webhook_operations_uses_filters(monkeypatch):
    db = _Db()
    current_user = _User(2)
    captured = {}

    def _fake_page(_db, *, limit, offset, query=None, event_type=None):
        captured["limit"] = limit
        captured["offset"] = offset
        captured["query"] = query
        captured["event_type"] = event_type
        return {
            "items": [{"id": 1, "event_type": "bot_webhook_metrics_reset"}],
            "total": 1,
            "offset": offset,
            "limit": limit,
            "has_more": False,
            "next_offset": None,
        }

    monkeypatch.setattr(moderation_api, "_webhook_operations_page", _fake_page)

    result = await moderation_api.list_webhook_operations(
        limit=25,
        offset=50,
        query="metrics",
        event_type="bot_webhook_metrics_reset",
        current_user=current_user,
        db=db,
    )

    assert captured == {
        "limit": 25,
        "offset": 50,
        "query": "metrics",
        "event_type": "bot_webhook_metrics_reset",
    }
    assert result["total"] == 1
    assert result["items"][0]["event_type"] == "bot_webhook_metrics_reset"


@pytest.mark.asyncio
async def test_export_webhook_operations_formats_lines(monkeypatch):
    db = _Db()
    current_user = _User(3)

    monkeypatch.setattr(
        moderation_api,
        "_webhook_operations_page",
        lambda *_args, **_kwargs: {
            "items": [
                {
                    "id": 10,
                    "event_type": "bot_webhook_queue_clear",
                    "created_at": "2026-07-01T20:00:00",
                    "user_id": 3,
                    "actor_name": "Admin",
                    "actor_username": "admin",
                    "metadata": {"queue_removed": 12},
                },
                {
                    "id": 11,
                    "event_type": "bot_webhook_metrics_reset",
                    "created_at": "2026-07-01T20:05:00",
                    "user_id": 3,
                    "actor_name": None,
                    "actor_username": None,
                    "metadata": {},
                },
            ],
            "total": 2,
            "offset": 0,
            "limit": 500,
            "has_more": True,
            "next_offset": 500,
        },
    )

    result = await moderation_api.export_webhook_operations(
        limit=500,
        query="bot_webhook",
        event_type=None,
        current_user=current_user,
        db=db,
    )

    assert result["count"] == 2
    assert result["truncated"] is True
    assert "bot_webhook_queue_clear" in result["content"]
    assert "Admin @admin" in result["content"]
    assert '{"queue_removed": 12}' in result["content"]


@pytest.mark.asyncio
async def test_export_webhook_incident_report_includes_sections(monkeypatch):
    db = _Db()
    current_user = _User(9)

    monkeypatch.setattr(
        moderation_api,
        "webhook_queue_stats",
        lambda: {"queue_depth": 2, "dead_depth": 1},
    )
    monkeypatch.setattr(
        moderation_api,
        "_build_webhook_alerts",
        lambda *_args, **_kwargs: {"items": [{"code": "dead_letter_backlog"}]},
    )
    monkeypatch.setattr(
        moderation_api,
        "_webhook_operations_page",
        lambda *_args, **_kwargs: {
            "items": [
                {
                    "id": 1,
                    "event_type": "bot_webhook_recovery_playbook_run",
                    "created_at": "2026-07-01T20:00:00",
                    "actor_name": "Ops",
                    "actor_username": "ops",
                    "metadata": {"requeued_dead_letters": 5},
                }
            ],
            "total": 1,
            "offset": 0,
            "limit": 200,
            "has_more": False,
            "next_offset": None,
        },
    )

    result = await moderation_api.export_webhook_incident_report(
        limit=200,
        query=None,
        event_type=None,
        current_user=current_user,
        db=db,
    )

    assert result["count"] == 1
    assert result["truncated"] is False
    assert "[queue_stats]" in result["content"]
    assert "[alerts]" in result["content"]
    assert "[operations]" in result["content"]
    assert "bot_webhook_recovery_playbook_run" in result["content"]


@pytest.mark.asyncio
async def test_list_dead_letter_supports_pagination_filters(monkeypatch):
    current_user = _User(11)
    captured = {}

    def _fake_page(*, limit, offset, query):
        captured["limit"] = limit
        captured["offset"] = offset
        captured["query"] = query
        return {
            "items": [{"task_id": "dlq_1", "drop_reason": "max_attempts_exhausted"}],
            "total": 3,
            "offset": offset,
            "limit": limit,
            "has_more": True,
            "next_offset": offset + limit,
        }

    monkeypatch.setattr(moderation_api, "webhook_dead_letter_page", _fake_page)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 3})

    result = await moderation_api.get_webhooks_dead_letter(
        limit=25,
        offset=50,
        query="max_attempts",
        current_user=current_user,
    )

    assert captured == {"limit": 25, "offset": 50, "query": "max_attempts"}
    assert result["total"] == 3
    assert result["has_more"] is True
    assert result["items"][0]["task_id"] == "dlq_1"


@pytest.mark.asyncio
async def test_requeue_dead_letter_accepts_selected_task_ids(monkeypatch):
    db = _Db()
    current_user = _User(12)
    captured = {}

    def _fake_requeue(*, limit, task_ids=None, query=None, drop_reason=None):
        captured["limit"] = limit
        captured["task_ids"] = task_ids
        captured["query"] = query
        captured["drop_reason"] = drop_reason
        return 2

    monkeypatch.setattr(moderation_api, "requeue_dead_letters", _fake_requeue)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 1})
    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", lambda *_a, **_k: None)

    body = moderation_api.WebhookDeadLetterActionRequest(
        limit=10,
        task_ids=["a1", "b2", "  "],
    )
    result = await moderation_api.requeue_webhooks_dead_letter(
        body=body,
        current_user=current_user,
        db=db,
    )

    assert captured["limit"] == 10
    assert captured["task_ids"] == ["a1", "b2", "  "]
    assert captured["query"] is None
    assert captured["drop_reason"] is None
    assert result["moved"] == 2
    assert db.commits == 1


@pytest.mark.asyncio
async def test_requeue_dead_letter_accepts_filter_presets(monkeypatch):
    db = _Db()
    current_user = _User(13)
    captured = {}

    def _fake_requeue(*, limit, task_ids=None, query=None, drop_reason=None):
        captured["limit"] = limit
        captured["task_ids"] = task_ids
        captured["query"] = query
        captured["drop_reason"] = drop_reason
        return 4

    monkeypatch.setattr(moderation_api, "requeue_dead_letters", _fake_requeue)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 9})
    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", lambda *_a, **_k: None)

    body = moderation_api.WebhookDeadLetterActionRequest(
        limit=50,
        query="max_attempts",
        drop_reason="max_attempts_exhausted",
    )
    result = await moderation_api.requeue_webhooks_dead_letter(
        body=body,
        current_user=current_user,
        db=db,
    )

    assert captured == {
        "limit": 50,
        "task_ids": None,
        "query": "max_attempts",
        "drop_reason": "max_attempts_exhausted",
    }
    assert result["moved"] == 4
    assert db.commits == 1


@pytest.mark.asyncio
async def test_requeue_dead_letter_audit_includes_filter_preset(monkeypatch):
    db = _Db()
    current_user = _User(21)
    captured = {}
    audit = {}

    def _fake_requeue(*, limit, task_ids=None, query=None, drop_reason=None):
        captured["limit"] = limit
        captured["task_ids"] = task_ids
        captured["query"] = query
        captured["drop_reason"] = drop_reason
        return 7

    def _fake_log(_db, *, current_user, action, metadata=None):
        audit["action"] = action
        audit["user_id"] = current_user.id
        audit["metadata"] = metadata or {}

    monkeypatch.setattr(moderation_api, "requeue_dead_letters", _fake_requeue)
    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", _fake_log)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 2})

    body = moderation_api.WebhookDeadLetterActionRequest(
        limit=120,
        query="rate",
        drop_reason="rate_limited_per_bot",
    )
    result = await moderation_api.requeue_webhooks_dead_letter(
        body=body,
        current_user=current_user,
        db=db,
    )

    assert captured == {
        "limit": 120,
        "task_ids": None,
        "query": "rate",
        "drop_reason": "rate_limited_per_bot",
    }
    assert audit["action"] == "bot_webhook_dead_letter_requeue"
    assert audit["user_id"] == 21
    assert audit["metadata"]["query"] == "rate"
    assert audit["metadata"]["drop_reason"] == "rate_limited_per_bot"
    assert result["moved"] == 7
    assert db.commits == 1


@pytest.mark.asyncio
async def test_moderation_webhook_runbook_flow_smoke(monkeypatch):
    db = _Db()
    current_user = _User(30)
    actions = []

    monkeypatch.setattr(
        moderation_api,
        "webhook_queue_stats",
        lambda: {
            "queue_depth": 1,
            "delayed_depth": 2,
            "dead_depth": 3,
            "dropped_total": 4,
            "throttled_total": 5,
        },
    )
    monkeypatch.setattr(
        moderation_api,
        "_build_webhook_alerts",
        lambda *_args, **_kwargs: {"items": [{"code": "dead_letter_backlog"}]},
    )
    monkeypatch.setattr(
        moderation_api,
        "_webhook_operations_page",
        lambda *_args, **_kwargs: {
            "items": [
                {
                    "id": 1,
                    "event_type": "bot_webhook_dead_letter_requeue",
                    "created_at": "2026-07-01T20:00:00",
                    "actor_name": "Admin",
                    "actor_username": "admin",
                    "metadata": {"moved": 3},
                }
            ],
            "total": 1,
            "offset": 0,
            "limit": 20,
            "has_more": False,
            "next_offset": None,
        },
    )
    monkeypatch.setattr(
        moderation_api,
        "requeue_dead_letters",
        lambda **kwargs: actions.append(("requeue", kwargs)) or 3,
    )
    monkeypatch.setattr(
        moderation_api,
        "force_promote_delayed",
        lambda **kwargs: actions.append(("promote", kwargs)) or 2,
    )
    monkeypatch.setattr(
        moderation_api,
        "_log_webhook_system_action",
        lambda _db, *, current_user, action, metadata=None: actions.append(
            ("audit", {"action": action, "metadata": metadata or {}, "user_id": current_user.id})
        ),
    )

    incident = await moderation_api.export_webhook_incident_report(
        limit=100,
        query=None,
        event_type=None,
        current_user=current_user,
        db=db,
    )
    assert incident["count"] == 1
    assert "[queue_stats]" in incident["content"]
    assert "[alerts]" in incident["content"]

    await moderation_api.requeue_webhooks_dead_letter(
        body=moderation_api.WebhookDeadLetterActionRequest(
            limit=100,
            drop_reason="max_attempts_exhausted",
        ),
        current_user=current_user,
        db=db,
    )
    await moderation_api.promote_webhook_delayed(
        body=moderation_api.WebhookQueuePromoteRequest(limit=100),
        current_user=current_user,
        db=db,
    )
    recovery = await moderation_api.run_webhooks_recovery_playbook(
        body=moderation_api.WebhookRecoveryPlaybookRequest(
            requeue_dead_limit=200,
            promote_delayed_limit=300,
        ),
        current_user=current_user,
        db=db,
    )

    assert recovery["status"] == "ok"
    assert db.commits == 3
    assert any(
        step[0] == "requeue" and step[1].get("drop_reason") == "max_attempts_exhausted"
        for step in actions
    )
    assert any(
        step[0] == "promote" and step[1].get("limit") == 100
        for step in actions
    )
    assert any(
        step[0] == "audit"
        and step[1].get("action") == "bot_webhook_recovery_playbook_run"
        and step[1].get("user_id") == 30
        for step in actions
    )


@pytest.mark.asyncio
async def test_requeue_dead_letter_clamps_limit_by_settings(monkeypatch):
    db = _Db()
    current_user = _User(40)
    captured = {}

    monkeypatch.setattr(
        moderation_api.settings,
        "BOT_WEBHOOK_OP_MAX_REQUEUE_LIMIT",
        25,
        raising=False,
    )

    def _fake_requeue(*, limit, task_ids=None, query=None, drop_reason=None):
        captured["limit"] = limit
        return 1

    monkeypatch.setattr(moderation_api, "requeue_dead_letters", _fake_requeue)
    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", lambda *_a, **_k: None)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 1})

    result = await moderation_api.requeue_webhooks_dead_letter(
        body=moderation_api.WebhookDeadLetterActionRequest(limit=999),
        current_user=current_user,
        db=db,
    )

    assert captured["limit"] == 25
    assert result["moved"] == 1
    assert db.commits == 1


@pytest.mark.asyncio
async def test_recovery_playbook_clamps_limits_by_settings(monkeypatch):
    db = _Db()
    current_user = _User(41)
    captured = {}

    monkeypatch.setattr(
        moderation_api.settings,
        "BOT_WEBHOOK_OP_MAX_RUNBOOK_REQUEUE_LIMIT",
        30,
        raising=False,
    )
    monkeypatch.setattr(
        moderation_api.settings,
        "BOT_WEBHOOK_OP_MAX_RUNBOOK_PROMOTE_LIMIT",
        35,
        raising=False,
    )

    monkeypatch.setattr(
        moderation_api,
        "requeue_dead_letters",
        lambda *, limit: captured.setdefault("requeue_limit", limit) or 2,
    )
    monkeypatch.setattr(
        moderation_api,
        "force_promote_delayed",
        lambda *, limit: captured.setdefault("promote_limit", limit) or 3,
    )
    monkeypatch.setattr(moderation_api, "_log_webhook_system_action", lambda *_a, **_k: None)
    monkeypatch.setattr(moderation_api, "webhook_queue_stats", lambda: {"dead_depth": 1})

    result = await moderation_api.run_webhooks_recovery_playbook(
        body=moderation_api.WebhookRecoveryPlaybookRequest(
            requeue_dead_limit=900,
            promote_delayed_limit=901,
        ),
        current_user=current_user,
        db=db,
    )

    assert captured["requeue_limit"] == 30
    assert captured["promote_limit"] == 35
    assert result["status"] == "ok"
    assert db.commits == 1
