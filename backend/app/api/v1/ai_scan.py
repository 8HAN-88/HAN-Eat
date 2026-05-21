"""
AI scan: кредиты, резерв перед анализом, статус для клиента (без pressure UX).
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.ai_scan_credits_service import (
    AiScanCreditsService,
    FREE_CAP,
    FREE_DAILY,
    FREE_START,
    PLUS_CAP,
    PLUS_DAILY,
    PLUS_START,
)
from app.services.analytics_service import AnalyticsService
from app.core.security import create_ai_scan_ticket
from app.core.entitlements import AI_SCANS_EXHAUSTED_CODE

router = APIRouter()


@router.get("/status")
async def ai_scan_status(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Начисление по суткам + UX-флаги без счётчиков для интерфейса."""
    svc = AiScanCreditsService(db)
    user = svc.refresh_user(current_user.id)
    meta = svc.status_meta(user)
    return {
        **meta,
        # legacy / analytics (клиент не показывает в UI)
        "scan_credits": int(user.scan_credits or 0),
        "last_free_warning": meta["soft_warning"],
    }


@router.post("/reserve")
async def ai_scan_reserve(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = AiScanCreditsService(db)
    ok, user, meta = svc.try_reserve_one_scan(current_user.id)

    analytics = AnalyticsService(db)
    if ok:
        analytics.log_event(
            event_type="ai_scan_reserve",
            entity_type="user",
            entity_id=current_user.id,
            user_id=current_user.id,
            metadata={
                "is_plus": meta.get("is_plus"),
                "credits_remaining": meta.get("credits_remaining"),
            },
        )
        db.commit()
        ticket = create_ai_scan_ticket(current_user.id)
        return {
            "ok": True,
            "ticket": ticket,
            "can_scan": True,
            "is_plus": meta.get("is_plus", False),
        }

    is_plus = meta.get("is_plus", False)
    analytics.log_event(
        event_type="ai_scan_paywall",
        entity_type="user",
        entity_id=current_user.id,
        user_id=current_user.id,
        metadata={"reason": "credits_exhausted", "is_plus": is_plus},
    )
    db.commit()

    if is_plus:
        msg = "AI-сканирования временно недоступны. Новые сканирования скоро появятся снова."
    else:
        msg = "Бесплатные AI-сканирования закончились"

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={
            "code": AI_SCANS_EXHAUSTED_CODE,
            "message": msg,
            "soft_paywall": True,
            "is_plus": is_plus,
        },
    )


@router.get("/limits")
async def ai_scan_limits_public():
    """Публичные лимиты (документация / админ; не для pressure UI)."""
    return {
        "free": {"start": FREE_START, "daily": FREE_DAILY, "max_bank": FREE_CAP},
        "ai": {"start": PLUS_START, "daily": PLUS_DAILY, "max_bank": PLUS_CAP},
        "pro": {"start": PLUS_START, "daily": PLUS_DAILY, "max_bank": PLUS_CAP},
    }
