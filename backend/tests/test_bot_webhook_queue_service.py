"""Smoke tests for bot webhook queue safeguards."""

from app.services import bot_webhook_queue_service as q


def _reset_local_state():
    q._local_queue.clear()
    q._local_delayed.clear()
    q._local_dead.clear()
    q._local_enqueue_windows.clear()
    for key in [
        q.METRIC_SENT,
        q.METRIC_FAILED,
        q.METRIC_RETRIED,
        q.METRIC_DROPPED,
        q.METRIC_THROTTLED,
    ]:
        q._local_metrics[key] = 0


def test_per_bot_rate_limit_moves_excess_to_dead_letter(monkeypatch):
    _reset_local_state()
    monkeypatch.setattr(q, "REDIS_IS_STUB", True)
    monkeypatch.setattr(q.settings, "BOT_WEBHOOK_MAX_PER_BOT_PER_MINUTE", 2)

    q.enqueue_webhook_task(bot_id=10, update_type="message", payload={"n": 1})
    q.enqueue_webhook_task(bot_id=10, update_type="message", payload={"n": 2})
    q.enqueue_webhook_task(
        bot_id=10,
        update_type="message",
        payload={"n": 3},
        delivery_id="delivery-3",
    )

    stats = q.webhook_queue_stats()
    dead_items = q.webhook_dead_letter_peek(limit=10)

    assert stats["queue_depth"] == 2
    assert stats["throttled_total"] == 1
    assert stats["dropped_total"] == 1
    assert dead_items
    assert dead_items[0]["drop_reason"] == "rate_limited_per_bot"
    assert dead_items[0]["delivery_id"] == "delivery-3"


def test_requeue_dead_letters_preserves_delivery_id(monkeypatch):
    _reset_local_state()
    monkeypatch.setattr(q, "REDIS_IS_STUB", True)
    monkeypatch.setattr(q.settings, "BOT_WEBHOOK_MAX_PER_BOT_PER_MINUTE", 1000)

    raw = q._serialize_task(
        {
            "task_id": "delivery-xyz",
            "bot_id": 42,
            "update_type": "webhook.test",
            "payload": {"ok": True},
            "attempt": 5,
            "queued_at": 123,
            "dropped_at": 124,
            "drop_reason": "max_attempts_exhausted",
        }
    )
    q._local_dead.append(raw)

    moved = q.requeue_dead_letters(limit=10)
    task = q._dequeue_webhook_task()

    assert moved == 1
    assert task is not None
    assert task["task_id"] == "delivery-xyz"
    assert task["attempt"] == 1
    assert task["bot_id"] == 42
