"""User event bus publish/subscribe."""
import asyncio

import pytest

from app.services.user_event_bus import publish_user_event, subscribe_user_events


@pytest.mark.asyncio
async def test_user_event_bus_local_publish_subscribe():
    received = []

    async def collect():
        async for event in subscribe_user_events(42):
            received.append(event)
            if len(received) >= 1:
                break

    task = asyncio.create_task(collect())
    await asyncio.sleep(0.05)
    publish_user_event(42, {"event": "notification.new", "notification_type": "like"})
    await asyncio.wait_for(task, timeout=2.0)

    assert received
    assert received[0]["event"] == "notification.new"
    assert received[0]["notification_type"] == "like"
