"""Публичные юридические страницы (для App Store / веб)."""
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse, HTMLResponse

router = APIRouter()

def _legal_file(name: str) -> Path:
    # backend/app/api/v1/legal.py -> repo root is parents[4]
    root = Path(__file__).resolve().parents[4]
    return root / "static" / "legal" / name


@router.get("/privacy", response_class=HTMLResponse)
async def privacy_policy():
    path = _legal_file("privacy.html")
    if path.is_file():
        return FileResponse(path, media_type="text/html; charset=utf-8")
    return HTMLResponse("<h1>Privacy</h1><p>Document not found.</p>", status_code=404)


@router.get("/terms", response_class=HTMLResponse)
async def terms_of_service():
    path = _legal_file("terms.html")
    if path.is_file():
        return FileResponse(path, media_type="text/html; charset=utf-8")
    return HTMLResponse("<h1>Terms</h1><p>Document not found.</p>", status_code=404)
