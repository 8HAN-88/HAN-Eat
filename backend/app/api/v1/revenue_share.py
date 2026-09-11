"""Реферальная программа и доп. реклама за долю."""
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
    code: str = Field(..., min_length=2, max_length=100)


def _svc_error(exc: RevenueShareError) -> HTTPException:
    return HTTPException(status_code=exc.status_code, detail=exc.message)


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
