"""Advertiser cabinet and ads review API."""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import (
    get_current_moderator_required,
    get_current_user_required,
)
from app.core.database import get_db
from app.models.user import User
from app.services.ads_service import AdsError, AdsService, MAX_ACTIVE_CAMPAIGNS, SURFACES

router = APIRouter()


class AdCreativeIn(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    cta_label: Optional[str] = None
    image_url: Optional[str] = None
    video_url: Optional[str] = None
    advertiser_name: Optional[str] = None


class AdCampaignIn(BaseModel):
    name: Optional[str] = None
    surfaces: Optional[list[str]] = None
    destination_type: Optional[str] = None
    destination_url: Optional[str] = None
    destination_channel_id: Optional[int] = None
    destination_post_id: Optional[int] = None
    starts_at: Optional[str] = None
    ends_at: Optional[str] = None
    daily_cap: Optional[int] = None
    creative: Optional[AdCreativeIn] = None


class AdRejectIn(BaseModel):
    reason: str = Field(..., min_length=2, max_length=400)


class AdEventIn(BaseModel):
    campaign_id: int
    kind: str = Field(..., pattern="^(impression|click)$")
    surface: str = "feed"


class AdHideIn(BaseModel):
    campaign_id: int


def _raise_ads(exc: AdsError) -> None:
    raise HTTPException(status_code=exc.status_code, detail=exc.message)


@router.get("/meta")
async def ads_meta():
    return {
        "surfaces": [
            {"id": "feed", "title": "Лента рекомендаций", "style": "instagram"},
            {"id": "reels", "title": "Рилсы", "style": "instagram"},
            {"id": "channel", "title": "Стена канала", "style": "telegram"},
        ],
        "destination_types": ["url", "channel", "post"],
        "max_active_campaigns": MAX_ACTIVE_CAMPAIGNS,
        "known_surfaces": list(SURFACES),
    }


@router.get("/inventory")
async def ads_inventory(
    surface: str = "feed",
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    key = (surface or "feed").strip().lower()
    if key not in SURFACES:
        key = "feed"
    return {"item": AdsService(db).pick_live_for_surface(surface=key, user_id=current_user.id)}


@router.get("/campaigns")
async def list_my_campaigns(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return {"campaigns": AdsService(db).list_mine(current_user.id)}


@router.post("/campaigns", status_code=201)
async def create_campaign(
    body: AdCampaignIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).create(current_user, body.model_dump(exclude_unset=True))
    except AdsError as exc:
        _raise_ads(exc)


@router.get("/campaigns/{campaign_id}")
async def get_campaign(
    campaign_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).get_mine(campaign_id, current_user.id)
    except AdsError as exc:
        _raise_ads(exc)


@router.patch("/campaigns/{campaign_id}")
async def update_campaign(
    campaign_id: int,
    body: AdCampaignIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).update(
            campaign_id, current_user, body.model_dump(exclude_unset=True)
        )
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/campaigns/{campaign_id}/submit")
async def submit_campaign(
    campaign_id: int,
    body: Optional[AdCampaignIn] = None,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        payload = body.model_dump(exclude_unset=True) if body else {}
        return AdsService(db).submit(campaign_id, current_user, payload)
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/campaigns/{campaign_id}/pause")
async def pause_campaign(
    campaign_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).pause(campaign_id, current_user)
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/campaigns/{campaign_id}/resume")
async def resume_campaign(
    campaign_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).resume(campaign_id, current_user)
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/campaigns/{campaign_id}/archive")
async def archive_campaign(
    campaign_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).archive(campaign_id, current_user)
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/events")
async def record_ad_event(
    body: AdEventIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).record_event(
            user_id=current_user.id,
            campaign_id=body.campaign_id,
            kind=body.kind,
            surface=body.surface,
        )
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/hide")
async def hide_ad(
    body: AdHideIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).hide_for_user(
            user_id=current_user.id,
            campaign_id=body.campaign_id,
        )
    except AdsError as exc:
        _raise_ads(exc)


@router.get("/review")
async def list_review_queue(
    status: str = "pending_review",
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    return {"campaigns": AdsService(db).list_review_queue(status=status)}


@router.post("/review/{campaign_id}/approve")
async def approve_campaign(
    campaign_id: int,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).approve(campaign_id, current_user)
    except AdsError as exc:
        _raise_ads(exc)


@router.post("/review/{campaign_id}/reject")
async def reject_campaign(
    campaign_id: int,
    body: AdRejectIn,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    try:
        return AdsService(db).reject(campaign_id, current_user, body.reason)
    except AdsError as exc:
        _raise_ads(exc)
