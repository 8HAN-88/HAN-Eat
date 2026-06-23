"""Pub/sub пользовательских событий (SSE): Redis + in-memory fallback."""
from __future__ import annotations

import asyncio
import json
import logging
import threading
from typing import Any, AsyncIterator, Dict, List

from app.core.redis_client import REDIS_IS_STUB, get_redis

logger = logging.getLogger(__name__)

_local_queues: Dict[str, List[asyncio.Queue]] = {}
_redis_listener_started: set[str] = set()
_redis_lock = threading.Lock()


def _channel(user_id: int) -> str:
    return f"user:events:{user_id}"


def publish_user_event(user_id: int, event: Dict[str, Any]) -> None:
    channel = _channel(user_id)
    for q in list(_local_queues.get(channel, [])):
        try:
            q.put_nowait(event)
        except Exception:
            pass
    if REDIS_IS_STUB:
        return
    try:
        get_redis().publish(channel, json.dumps(event, default=str))
    except Exception as e:
        logger.debug("user_event_bus publish failed: %s", e)


def _ensure_redis_listener(channel: str, loop: asyncio.AbstractEventLoop) -> None:
    with _redis_lock:
        if channel in _redis_listener_started:
            return
        _redis_listener_started.add(channel)

    def run() -> None:
        try:
            pubsub = get_redis().pubsub(ignore_subscribe_messages=True)
            pubsub.subscribe(channel)
            for msg in pubsub.listen():
                if msg.get("type") != "message":
                    continue
                try:
                    event = json.loads(msg["data"])
                except Exception:
                    continue
                for q in list(_local_queues.get(channel, [])):
                    loop.call_soon_threadsafe(q.put_nowait, event)
        except Exception as e:
            logger.debug("user_event_bus redis listener stopped: %s", e)
            with _redis_lock:
                _redis_listener_started.discard(channel)

    threading.Thread(target=run, daemon=True, name=f"user-redis-{channel}").start()


async def subscribe_user_events(user_id: int) -> AsyncIterator[Dict[str, Any]]:
    channel = _channel(user_id)
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue()
    _local_queues.setdefault(channel, []).append(q)
    if not REDIS_IS_STUB:
        _ensure_redis_listener(channel, loop)

    try:
        while True:
            event = await q.get()
            yield event
    finally:
        queues = _local_queues.get(channel, [])
        if q in queues:
            queues.remove(q)
