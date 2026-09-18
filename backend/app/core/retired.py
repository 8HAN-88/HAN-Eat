"""Ответы для снятых разделов (кухня и т.п.)."""

from __future__ import annotations

from fastapi import status
from fastapi.responses import JSONResponse

KITCHEN_GONE_MESSAGE = "Этот раздел удалён. HanWe — мессенджер."

KITCHEN_GONE_DETAIL = {
    "code": "kitchen_retired",
    "message": KITCHEN_GONE_MESSAGE,
}


def kitchen_gone_response() -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_410_GONE,
        content={
            "detail": KITCHEN_GONE_DETAIL,
            "code": "kitchen_retired",
        },
    )
