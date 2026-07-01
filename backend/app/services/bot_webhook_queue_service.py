"""Асинхронная очередь доставки bot webhook update-ов."""
from __future__ import annotations

import asyncio
import heapq
import json
import logging
import secrets
import time
from typing import Any, Dict, List, Tuple

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.redis_client import REDIS_IS_STUB, get_redis
from app.models.user import User
from app.services.bot_webhook_service import deliver_webhook_update

logger = logging.getLogger(__name__)

QUEUE_KEY = "bot:webhook:queue"
DELAYED_KEY = "bot:webhook:delayed"
DEAD_KEY = "bot:webhook:dead"
METRIC_SENT = "bot:webhook:metric:sent"
METRIC_FAILED = "bot:webhook:metric:failed"
METRIC_RETRIED = "bot:webhook:metric:retried"
METRIC_DROPPED = "bot:webhook:metric:dropped"
METRIC_THROTTLED = "bot:webhook:metric:throttled"
DEAD_KEEP_MAX = 5000

_local_queue: List[str] = []
_local_delayed: List[Tuple[float, str]] = []
_local_dead: List[str] = []
_local_enqueue_windows: Dict[int, Tuple[int, int]] = {}
_local_metrics: Dict[str, int] = {
    METRIC_SENT: 0,
    METRIC_FAILED: 0,
    METRIC_RETRIED: 0,
    METRIC_DROPPED: 0,
    METRIC_THROTTLED: 0,
}


def _serialize_task(task: Dict[str, Any]) -> str:
    return json.dumps(task, ensure_ascii=False, separators=(",", ":"))


def _deserialize_task(raw: str) -> Dict[str, Any]:
    return json.loads(raw)


def _enqueue_local(task_json: str, delay_seconds: float = 0.0) -> None:
    if delay_seconds <= 0:
        _local_queue.append(task_json)
        return
    heapq.heappush(_local_delayed, (time.time() + delay_seconds, task_json))


def _inc_metric(key: str, amount: int = 1) -> None:
    if REDIS_IS_STUB:
        _local_metrics[key] = _local_metrics.get(key, 0) + amount
        return
    try:
        get_redis().incr(key, amount)
    except Exception:
        _local_metrics[key] = _local_metrics.get(key, 0) + amount


def _promote_local_due() -> None:
    now = time.time()
    while _local_delayed and _local_delayed[0][0] <= now:
        _, payload = heapq.heappop(_local_delayed)
        _local_queue.append(payload)


def _allow_enqueue_for_bot(bot_id: int) -> bool:
    limit = max(0, int(getattr(settings, "BOT_WEBHOOK_MAX_PER_BOT_PER_MINUTE", 120)))
    if limit <= 0:
        return True
    now_bucket = int(time.time() // 60)
    if REDIS_IS_STUB:
        prev = _local_enqueue_windows.get(bot_id)
        if not prev or prev[0] != now_bucket:
            _local_enqueue_windows[bot_id] = (now_bucket, 1)
            return True
        count = prev[1] + 1
        _local_enqueue_windows[bot_id] = (now_bucket, count)
        return count <= limit
    key = f"bot:webhook:enqueue:{bot_id}:{now_bucket}"
    try:
        redis = get_redis()
        count = int(redis.incr(key))
        redis.expire(key, 120)
        return count <= limit
    except Exception:
        prev = _local_enqueue_windows.get(bot_id)
        if not prev or prev[0] != now_bucket:
            _local_enqueue_windows[bot_id] = (now_bucket, 1)
            return True
        count = prev[1] + 1
        _local_enqueue_windows[bot_id] = (now_bucket, count)
        return count <= limit


def enqueue_webhook_task(
    *,
    bot_id: int,
    update_type: str,
    payload: Dict[str, Any],
    attempt: int = 1,
    delivery_id: str | None = None,
) -> None:
    bot_id_i = int(bot_id)
    if not _allow_enqueue_for_bot(bot_id_i):
        _inc_metric(METRIC_THROTTLED)
        _inc_metric(METRIC_DROPPED)
        rejected_task = {
            "task_id": (delivery_id or secrets.token_hex(8)).strip()[:64],
            "bot_id": bot_id_i,
            "update_type": update_type,
            "payload": payload,
            "attempt": int(attempt),
            "queued_at": int(time.time()),
        }
        _push_dead_letter(rejected_task, reason="rate_limited_per_bot")
        return

    task_id = (delivery_id or secrets.token_hex(8)).strip()[:64]
    task = {
        "task_id": task_id,
        "bot_id": bot_id_i,
        "update_type": update_type,
        "payload": payload,
        "attempt": int(attempt),
        "queued_at": int(time.time()),
    }
    raw = _serialize_task(task)
    if REDIS_IS_STUB:
        _enqueue_local(raw)
        return
    try:
        get_redis().lpush(QUEUE_KEY, raw)
    except Exception as e:  # noqa: BLE001
        logger.debug("enqueue_webhook_task failed, fallback local queue: %s", e)
        _enqueue_local(raw)


def _promote_delayed_due_redis(batch: int = 50) -> None:
    now = int(time.time())
    redis = get_redis()
    try:
        items = redis.zrangebyscore(DELAYED_KEY, min=0, max=now, start=0, num=batch)
        if not items:
            return
        for item in items:
            redis.lpush(QUEUE_KEY, item)
            redis.zrem(DELAYED_KEY, item)
    except Exception as e:  # noqa: BLE001
        logger.debug("promote delayed webhook tasks failed: %s", e)


def _dequeue_webhook_task() -> Dict[str, Any] | None:
    if REDIS_IS_STUB:
        _promote_local_due()
        if not _local_queue:
            return None
        return _deserialize_task(_local_queue.pop(0))
    _promote_delayed_due_redis()
    try:
        raw = get_redis().rpop(QUEUE_KEY)
    except Exception as e:  # noqa: BLE001
        logger.debug("dequeue webhook task failed: %s", e)
        return None
    if not raw:
        return None
    try:
        return _deserialize_task(raw)
    except Exception:
        return None


def _schedule_retry(task: Dict[str, Any], delay_seconds: float) -> None:
    raw = _serialize_task(task)
    if REDIS_IS_STUB:
        _enqueue_local(raw, delay_seconds=delay_seconds)
        return
    try:
        eta = int(time.time() + max(1.0, delay_seconds))
        get_redis().zadd(DELAYED_KEY, {raw: eta})
        _inc_metric(METRIC_RETRIED)
    except Exception as e:  # noqa: BLE001
        logger.debug("schedule retry failed, fallback local queue: %s", e)
        _enqueue_local(raw, delay_seconds=delay_seconds)
        _inc_metric(METRIC_RETRIED)


def _push_dead_letter(task: Dict[str, Any], reason: str) -> None:
    dead_task = dict(task)
    dead_task["drop_reason"] = reason
    dead_task["dropped_at"] = int(time.time())
    raw = _serialize_task(dead_task)
    if REDIS_IS_STUB:
        _local_dead.append(raw)
        if len(_local_dead) > DEAD_KEEP_MAX:
            del _local_dead[: len(_local_dead) - DEAD_KEEP_MAX]
        return
    redis = get_redis()
    try:
        redis.lpush(DEAD_KEY, raw)
        redis.ltrim(DEAD_KEY, 0, DEAD_KEEP_MAX - 1)
    except Exception as e:  # noqa: BLE001
        logger.debug("push dead letter failed, fallback local list: %s", e)
        _local_dead.append(raw)
        if len(_local_dead) > DEAD_KEEP_MAX:
            del _local_dead[: len(_local_dead) - DEAD_KEEP_MAX]


def _process_task(task: Dict[str, Any]) -> None:
    bot_id = int(task.get("bot_id") or 0)
    if bot_id <= 0:
        return
    update_type = str(task.get("update_type") or "").strip()
    payload = task.get("payload")
    if not update_type or not isinstance(payload, dict):
        return
    attempt = max(1, int(task.get("attempt") or 1))
    db = SessionLocal()
    try:
        bot = db.query(User).filter(User.id == bot_id, User.is_bot.is_(True)).first()
        if not bot or not bot.bot_webhook_enabled or not bot.bot_webhook_url:
            db.rollback()
            return
        ok = deliver_webhook_update(
            db,
            bot_user=bot,
            update_type=update_type,
            payload=payload,
            delivery_id=str(task.get("task_id") or "").strip() or None,
        )
        max_attempts = max(1, int(getattr(settings, "BOT_WEBHOOK_DELIVERY_MAX_ATTEMPTS", 5)))
        if ok:
            _inc_metric(METRIC_SENT)
            db.commit()
            return
        _inc_metric(METRIC_FAILED)
        db.commit()
        if attempt >= max_attempts:
            _inc_metric(METRIC_DROPPED)
            _push_dead_letter(task, reason="max_attempts_exhausted")
            return
        next_task = dict(task)
        next_task["attempt"] = attempt + 1
        backoff = min(300.0, float(2 ** attempt))
        _schedule_retry(next_task, backoff)
    except Exception:  # noqa: BLE001
        db.rollback()
        logger.exception("bot webhook queue task failed")
    finally:
        db.close()


async def run_webhook_queue_worker() -> None:
    if not getattr(settings, "BOT_WEBHOOK_QUEUE_ENABLED", True):
        logger.info("Bot webhook queue disabled by config")
        return
    poll = max(0.2, float(getattr(settings, "BOT_WEBHOOK_QUEUE_POLL_SECONDS", 1.0)))
    logger.info("Bot webhook queue worker started")
    while True:
        task = _dequeue_webhook_task()
        if task is None:
            await asyncio.sleep(poll)
            continue
        _process_task(task)


def webhook_queue_stats() -> Dict[str, int]:
    if REDIS_IS_STUB:
        _promote_local_due()
        return {
            "queue_depth": len(_local_queue),
            "delayed_depth": len(_local_delayed),
            "dead_depth": len(_local_dead),
            "sent_total": _local_metrics.get(METRIC_SENT, 0),
            "failed_total": _local_metrics.get(METRIC_FAILED, 0),
            "retried_total": _local_metrics.get(METRIC_RETRIED, 0),
            "dropped_total": _local_metrics.get(METRIC_DROPPED, 0),
            "throttled_total": _local_metrics.get(METRIC_THROTTLED, 0),
            "redis_stub": 1,
        }
    redis = get_redis()
    try:
        queue_depth = int(redis.llen(QUEUE_KEY) or 0)
    except Exception:
        queue_depth = 0
    try:
        delayed_depth = int(redis.zcard(DELAYED_KEY) or 0)
    except Exception:
        delayed_depth = 0
    try:
        dead_depth = int(redis.llen(DEAD_KEY) or 0)
    except Exception:
        dead_depth = len(_local_dead)

    def _get_counter(key: str) -> int:
        try:
            value = redis.get(key)
            if value is None:
                return _local_metrics.get(key, 0)
            return int(value)
        except Exception:
            return _local_metrics.get(key, 0)

    return {
        "queue_depth": queue_depth,
        "delayed_depth": delayed_depth,
        "dead_depth": dead_depth,
        "sent_total": _get_counter(METRIC_SENT),
        "failed_total": _get_counter(METRIC_FAILED),
        "retried_total": _get_counter(METRIC_RETRIED),
        "dropped_total": _get_counter(METRIC_DROPPED),
        "throttled_total": _get_counter(METRIC_THROTTLED),
        "redis_stub": 0,
    }


def force_promote_delayed(limit: int = 500) -> int:
    """Принудительно переносит delayed-задачи в основную очередь."""
    max_items = max(1, int(limit))
    if REDIS_IS_STUB:
        moved = 0
        while _local_delayed and moved < max_items:
            _, payload = heapq.heappop(_local_delayed)
            _local_queue.append(payload)
            moved += 1
        return moved
    redis = get_redis()
    moved = 0
    try:
        items = redis.zrange(DELAYED_KEY, 0, max_items - 1)
        for item in items:
            redis.lpush(QUEUE_KEY, item)
            redis.zrem(DELAYED_KEY, item)
            moved += 1
    except Exception as e:  # noqa: BLE001
        logger.debug("force_promote_delayed failed: %s", e)
    return moved


def clear_webhook_queue(include_delayed: bool = True) -> Dict[str, int]:
    """Очищает очередь webhook-доставки."""
    if REDIS_IS_STUB:
        queue_removed = len(_local_queue)
        _local_queue.clear()
        delayed_removed = 0
        if include_delayed:
            delayed_removed = len(_local_delayed)
            _local_delayed.clear()
        return {"queue_removed": queue_removed, "delayed_removed": delayed_removed}

    redis = get_redis()
    queue_removed = 0
    delayed_removed = 0
    try:
        queue_removed = int(redis.llen(QUEUE_KEY) or 0)
        redis.delete(QUEUE_KEY)
    except Exception as e:  # noqa: BLE001
        logger.debug("clear queue failed: %s", e)
    if include_delayed:
        try:
            delayed_removed = int(redis.zcard(DELAYED_KEY) or 0)
            redis.delete(DELAYED_KEY)
        except Exception as e:  # noqa: BLE001
            logger.debug("clear delayed failed: %s", e)
    return {"queue_removed": queue_removed, "delayed_removed": delayed_removed}


def reset_webhook_metrics() -> Dict[str, int]:
    """Сбрасывает счетчики webhook-метрик."""
    keys = [METRIC_SENT, METRIC_FAILED, METRIC_RETRIED, METRIC_DROPPED, METRIC_THROTTLED]
    for key in keys:
        _local_metrics[key] = 0
    if REDIS_IS_STUB:
        return webhook_queue_stats()
    try:
        get_redis().delete(*keys)
    except Exception as e:  # noqa: BLE001
        logger.debug("reset_webhook_metrics failed: %s", e)
    return webhook_queue_stats()


def _dead_raw_items() -> List[str]:
    if REDIS_IS_STUB:
        return list(reversed(_local_dead))
    try:
        return list(get_redis().lrange(DEAD_KEY, 0, DEAD_KEEP_MAX - 1))
    except Exception as e:  # noqa: BLE001
        logger.debug("dead raw items fallback local: %s", e)
        return list(reversed(_local_dead))


def _dead_summary_from_raw(raw: str) -> Dict[str, Any] | None:
    try:
        row = _deserialize_task(raw)
    except Exception:
        return None
    if not isinstance(row, dict):
        return None
    return {
        "task_id": row.get("task_id"),
        "bot_id": row.get("bot_id"),
        "update_type": row.get("update_type"),
        "delivery_id": row.get("task_id"),
        "attempt": row.get("attempt"),
        "queued_at": row.get("queued_at"),
        "dropped_at": row.get("dropped_at"),
        "drop_reason": row.get("drop_reason"),
    }


def webhook_dead_letter_peek(limit: int = 50) -> List[Dict[str, Any]]:
    page = webhook_dead_letter_page(limit=limit, offset=0, query=None)
    return page.get("items", [])


def webhook_dead_letter_page(
    *,
    limit: int = 50,
    offset: int = 0,
    query: str | None = None,
) -> Dict[str, Any]:
    page_limit = max(1, min(200, int(limit)))
    page_offset = max(0, int(offset))
    query_text = (query or "").strip().lower()
    rows = [item for item in (_dead_summary_from_raw(raw) for raw in _dead_raw_items()) if item]
    if query_text:
        rows = [
            row
            for row in rows
            if query_text in str(row.get("task_id") or "").lower()
            or query_text in str(row.get("bot_id") or "").lower()
            or query_text in str(row.get("update_type") or "").lower()
            or query_text in str(row.get("drop_reason") or "").lower()
        ]
    total = len(rows)
    items = rows[page_offset : page_offset + page_limit]
    has_more = page_offset + len(items) < total
    return {
        "items": items,
        "total": total,
        "offset": page_offset,
        "limit": page_limit,
        "has_more": has_more,
        "next_offset": page_offset + page_limit if has_more else None,
    }


def requeue_dead_letters(
    limit: int = 100,
    task_ids: List[str] | None = None,
    query: str | None = None,
    drop_reason: str | None = None,
) -> int:
    max_items = max(1, min(500, int(limit)))
    selected = {str(task_id).strip() for task_id in (task_ids or []) if str(task_id).strip()}
    query_text = (query or "").strip().lower()
    drop_reason_text = (drop_reason or "").strip().lower()
    moved = 0

    def _task_matches(task: Dict[str, Any], *, task_id: str) -> bool:
        if selected and task_id not in selected:
            return False
        if drop_reason_text and str(task.get("drop_reason") or "").strip().lower() != drop_reason_text:
            return False
        if query_text:
            if (
                query_text not in task_id.lower()
                and query_text not in str(task.get("bot_id") or "").lower()
                and query_text not in str(task.get("update_type") or "").lower()
                and query_text not in str(task.get("drop_reason") or "").lower()
            ):
                return False
        return True

    if REDIS_IS_STUB:
        kept: List[str] = []
        while _local_dead:
            raw = _local_dead.pop()
            try:
                task = _deserialize_task(raw)
            except Exception:
                continue
            if not isinstance(task, dict):
                continue
            task_id = str(task.get("task_id") or "").strip()
            if not _task_matches(task, task_id=task_id):
                kept.append(raw)
                continue
            if moved >= max_items:
                kept.append(raw)
                continue
            bot_id = int(task.get("bot_id") or 0)
            update_type = str(task.get("update_type") or "").strip()
            payload = task.get("payload")
            if bot_id <= 0 or not update_type or not isinstance(payload, dict):
                continue
            enqueue_webhook_task(
                bot_id=bot_id,
                update_type=update_type,
                payload=payload,
                attempt=1,
                delivery_id=task_id or None,
            )
            moved += 1
        _local_dead.extend(reversed(kept))
        return moved

    redis = get_redis()
    has_filter = bool(selected or query_text or drop_reason_text)
    if not has_filter:
        while moved < max_items:
            try:
                raw = redis.rpop(DEAD_KEY)
            except Exception as e:  # noqa: BLE001
                logger.debug("requeue_dead_letters pop failed: %s", e)
                break
            if not raw:
                break
            try:
                task = _deserialize_task(raw)
            except Exception:
                continue
            if not isinstance(task, dict):
                continue
            bot_id = int(task.get("bot_id") or 0)
            update_type = str(task.get("update_type") or "").strip()
            payload = task.get("payload")
            task_id = str(task.get("task_id") or "").strip()
            if bot_id <= 0 or not update_type or not isinstance(payload, dict):
                continue
            enqueue_webhook_task(
                bot_id=bot_id,
                update_type=update_type,
                payload=payload,
                attempt=1,
                delivery_id=task_id or None,
            )
            moved += 1
        return moved

    try:
        candidates = list(redis.lrange(DEAD_KEY, 0, DEAD_KEEP_MAX - 1))
    except Exception as e:  # noqa: BLE001
        logger.debug("requeue_dead_letters selected lrange failed: %s", e)
        return 0
    for raw in candidates:
        if moved >= max_items:
            break
        try:
            task = _deserialize_task(raw)
        except Exception:
            continue
        if not isinstance(task, dict):
            continue
        task_id = str(task.get("task_id") or "").strip()
        if not _task_matches(task, task_id=task_id):
            continue
        try:
            removed = int(redis.lrem(DEAD_KEY, 1, raw) or 0)
        except Exception as e:  # noqa: BLE001
            logger.debug("requeue_dead_letters selected lrem failed: %s", e)
            continue
        if removed <= 0:
            continue
        bot_id = int(task.get("bot_id") or 0)
        update_type = str(task.get("update_type") or "").strip()
        payload = task.get("payload")
        if bot_id <= 0 or not update_type or not isinstance(payload, dict):
            continue
        enqueue_webhook_task(
            bot_id=bot_id,
            update_type=update_type,
            payload=payload,
            attempt=1,
            delivery_id=task_id or None,
        )
        moved += 1
    return moved


def clear_dead_letters() -> int:
    if REDIS_IS_STUB:
        removed = len(_local_dead)
        _local_dead.clear()
        return removed
    redis = get_redis()
    removed = 0
    try:
        removed = int(redis.llen(DEAD_KEY) or 0)
        redis.delete(DEAD_KEY)
    except Exception as e:  # noqa: BLE001
        logger.debug("clear_dead_letters failed: %s", e)
    return removed
