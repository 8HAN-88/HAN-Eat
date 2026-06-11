"""Link preview API (Open Graph proxy)."""
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.link_preview_service import fetch_link_preview

router = APIRouter()


@router.get("/link-preview")
async def get_link_preview(
    url: str = Query(..., min_length=8, max_length=2048),
    current_user: User = Depends(get_current_user_required),
):
    del current_user
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
