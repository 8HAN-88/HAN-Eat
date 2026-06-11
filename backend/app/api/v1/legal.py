"""Публичные юридические страницы и API согласия."""
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.schemas.auth import LegalAcceptRequest
from app.services.legal_consent_service import (
    consent_required,
    legal_status_payload,
    record_consent,
    user_legal_fields,
)

pages_router = APIRouter()
api_router = APIRouter()
# Совместимость: main подключает pages_router как legal.router
router = pages_router


def _legal_file(name: str) -> Path:
    root = Path(__file__).resolve().parents[4]
    return root / "static" / "legal" / name


@pages_router.get("/privacy")
async def privacy_policy():
    path = _legal_file("privacy.html")
    if path.is_file():
        from fastapi.responses import FileResponse

        return FileResponse(path, media_type="text/html; charset=utf-8")
    from fastapi.responses import HTMLResponse

    return HTMLResponse("<h1>Privacy</h1><p>Document not found.</p>", status_code=404)


@pages_router.get("/terms")
async def terms_of_service():
    path = _legal_file("terms.html")
    if path.is_file():
        from fastapi.responses import FileResponse

        return FileResponse(path, media_type="text/html; charset=utf-8")
    from fastapi.responses import HTMLResponse

    return HTMLResponse("<h1>Terms</h1><p>Document not found.</p>", status_code=404)


@api_router.get("/status")
async def legal_status():
    """Актуальная версия документов и тексты для UI согласия."""
    return legal_status_payload()


@api_router.post("/accept")
async def accept_legal(
    body: LegalAcceptRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if not body.accept_legal:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "LEGAL_CONSENT_REQUIRED",
                "message": "Необходимо подтвердить согласие",
            },
        )
    record_consent(current_user, db)
    db.commit()
    db.refresh(current_user)
    return {
        "accepted": True,
        **user_legal_fields(current_user),
    }


@api_router.get("/me")
async def legal_me(current_user: User = Depends(get_current_user_required)):
    return {
        **user_legal_fields(current_user),
        **legal_status_payload(),
        "consent_required": consent_required(current_user),
    }
