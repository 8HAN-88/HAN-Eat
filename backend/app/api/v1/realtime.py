"""Единый SSE-поток пользовательских событий (уведомления, счётчики)."""
from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.user_event_bus import subscribe_user_events

router = APIRouter()


@router.get("/stream")
async def user_realtime_stream(
    current_user: User = Depends(get_current_user_required),
):
    async def generate():
        yield ": connected\n\n"
        try:
            event_iter = subscribe_user_events(current_user.id).__aiter__()
            while True:
                try:
                    event = await asyncio.wait_for(
                        event_iter.__anext__(), timeout=25.0
                    )
                    yield f"data: {json.dumps(event, default=str)}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"
                except StopAsyncIteration:
                    break
        except asyncio.CancelledError:
            raise
        except Exception:
            yield 'data: {"event":"error"}\n\n'

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
