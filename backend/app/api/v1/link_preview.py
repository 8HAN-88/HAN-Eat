"""Link preview API (Open Graph proxy) + public OG HTML for own posts."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.services.link_preview_service import (
    fetch_link_preview,
    render_own_og_html,
    try_own_content_preview,
)

router = APIRouter()


@router.get("/link-preview")
async def get_link_preview(
    url: str = Query(..., min_length=8, max_length=2048),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    del current_user
    own = try_own_content_preview(db, url)
    if own:
        return own
    try:
        preview = fetch_link_preview(url)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not fetch preview",
        )
    if not preview.get("title") and not preview.get("description"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No preview available",
        )
    return preview


@router.get("/og/{kind}/{post_id}", response_class=HTMLResponse)
async def og_share_page(
    kind: str,
    post_id: int,
    db: Session = Depends(get_db),
):
    """Public HTML with OG tags for Telegram / iMessage / first-hop /reel/:id."""
    if kind not in ("reel", "post"):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    preview = try_own_content_preview(db, f"https://haneat.app/{kind}/{post_id}")
    if preview is None:
        preview = {
            "url": f"https://haneat.app/{kind}/{post_id}",
            "title": "HanWe",
            "description": "Открыть в HanWe",
            "image_url": "https://haneat.app/app/icons/Icon-512.png",
            "site_name": "HanWe",
        }
    return HTMLResponse(
        render_own_og_html(preview, kind=kind, post_id=post_id),
        headers={"Cache-Control": "public, max-age=300"},
    )
