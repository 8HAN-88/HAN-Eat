"""Реферальная программа и доп. реклама за долю."""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.services.revenue_share_service import RevenueShareError, RevenueShareService

router = APIRouter()


class ExtraAdsIn(BaseModel):
    enabled: bool


class ApplyCodeIn(BaseModel):
    code: str = Field(..., min_length=2, max_length=500)


class ConvertStarsIn(BaseModel):
    amount_kopecks: Optional[int] = Field(default=None, ge=1)


class CardPayoutIn(BaseModel):
    amount_kopecks: Optional[int] = Field(default=None, ge=1)
    phone: str = Field(..., min_length=10, max_length=32)
    recipient_name: str = Field(..., min_length=2, max_length=80)
    note: Optional[str] = Field(default=None, max_length=512)


class ReviewPayoutIn(BaseModel):
    approve: bool
    note: Optional[str] = Field(default=None, max_length=512)


def _svc_error(exc: RevenueShareError) -> HTTPException:
    return HTTPException(status_code=exc.status_code, detail=exc.message)


def _with_last(svc: RevenueShareService, user: User, payout) -> dict:
    snap = svc.snapshot(user)
    snap["last_payout"] = svc._payout_dict(payout)
    return snap


@router.get("/me")
def my_revenue_share(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    return RevenueShareService(db).snapshot(user)


@router.post("/extra-ads")
def set_extra_ads(
    body: ExtraAdsIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    svc = RevenueShareService(db)
    svc.set_extra_ads(user, body.enabled)
    return svc.snapshot(user)


@router.post("/apply-code")
def apply_referral_code(
    body: ApplyCodeIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    svc = RevenueShareService(db)
    try:
        svc.apply_code(user, body.code)
    except RevenueShareError as exc:
        raise _svc_error(exc) from exc
    return svc.snapshot(user)


@router.post("/payouts/stars")
def convert_available_to_stars(
    body: ConvertStarsIn | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    svc = RevenueShareService(db)
    try:
        payout = svc.convert_to_stars(
            user,
            None if body is None else body.amount_kopecks,
        )
    except RevenueShareError as exc:
        raise _svc_error(exc) from exc
    return _with_last(svc, user, payout)


@router.post("/payouts/card")
def request_card_payout(
    body: CardPayoutIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    svc = RevenueShareService(db)
    try:
        payout = svc.request_card_payout(
            user,
            amount_kopecks=body.amount_kopecks,
            phone=body.phone,
            recipient_name=body.recipient_name,
            note=body.note,
        )
    except RevenueShareError as exc:
        raise _svc_error(exc) from exc
    return _with_last(svc, user, payout)


@router.get("/payouts/me")
def list_my_payouts(
    limit: int = 40,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    svc = RevenueShareService(db)
    return [svc._payout_dict(row) for row in svc.list_my_payouts(user.id, limit=limit)]


@router.get("/payouts/queue")
def admin_payout_queue(
    status: Optional[str] = "pending",
    limit: int = 100,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Нужны права администратора")
    return RevenueShareService(db).list_payout_queue(status=status, limit=limit)


@router.post("/payouts/{payout_id}/review")
def review_partner_payout(
    payout_id: int,
    body: ReviewPayoutIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_required),
):
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Нужны права администратора")
    svc = RevenueShareService(db)
    try:
        payout = svc.review_payout(
            payout_id,
            reviewer_user_id=user.id,
            approve=body.approve,
            note=body.note,
        )
    except RevenueShareError as exc:
        raise _svc_error(exc) from exc
    db.commit()
    db.refresh(payout)
    return svc._payout_dict(payout, with_user=True)
