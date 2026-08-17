"""Flexible leveled subscription API."""
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_admin_required, get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.schemas.flex_subscription import (
    FlexBlockWrite,
    FlexFeatureWrite,
    FlexLevelRequest,
    FlexMeResponse,
    FlexMoveRequest,
    FlexPreviewResponse,
    FlexSaveLayoutRequest,
    FlexShopResponse,
)
from app.services.flex_subscription_service import FlexSubscriptionService, price_for_level

router = APIRouter(prefix="/flex", tags=["Flex subscription"])


def _svc(db: Session) -> FlexSubscriptionService:
    return FlexSubscriptionService(db)


@router.get("/me", response_model=FlexMeResponse)
def get_my_flex(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return _svc(db).me_payload(current_user.id)


@router.get("/shop", response_model=FlexShopResponse)
def get_flex_shop(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return _svc(db).shop_payload(current_user.id)


@router.post("/preview", response_model=FlexPreviewResponse)
def preview_flex(
    request: FlexLevelRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    return _svc(db).preview_payload(current_user.id, request.level)


@router.post("/layout")
def save_flex_layout(
    request: FlexSaveLayoutRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = _svc(db)
    service.save_layout(
        current_user.id,
        [s.model_dump() for s in request.slots],
    )
    db.commit()
    return service.me_payload(current_user.id)


@router.post("/move")
def move_flex_feature(
    request: FlexMoveRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    service = _svc(db)
    service.move_feature(current_user.id, request.feature_id, request.target_level)
    db.commit()
    return service.me_payload(current_user.id)


@router.get("/admin/features")
def admin_list_features(
    _: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    service = _svc(db)
    return {
        "blocks": [service._block_item(b) for b in service.list_blocks()],
        "features": [
            service._feature_item(f, f.default_level, set())
            for f in service.list_features(include_inactive=True)
        ],
    }


@router.post("/admin/features", status_code=status.HTTP_201_CREATED)
def admin_create_feature(
    request: FlexFeatureWrite,
    _: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    feat = _svc(db).create_feature(request.model_dump(exclude_unset=True))
    db.commit()
    db.refresh(feat)
    return FlexSubscriptionService._feature_item(feat, feat.default_level, set())


@router.patch("/admin/features/{feature_id}")
def admin_update_feature(
    feature_id: int,
    request: FlexFeatureWrite,
    _: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    feat = _svc(db).update_feature(feature_id, request.model_dump(exclude_unset=True))
    db.commit()
    db.refresh(feat)
    return FlexSubscriptionService._feature_item(feat, feat.default_level, set())


@router.post("/admin/blocks")
def admin_upsert_block(
    request: FlexBlockWrite,
    _: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    block = _svc(db).upsert_block(request.model_dump(exclude_unset=True))
    db.commit()
    db.refresh(block)
    return FlexSubscriptionService._block_item(block)


@router.patch("/admin/blocks/{block_id}")
def admin_update_block(
    block_id: int,
    request: FlexBlockWrite,
    _: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    block = _svc(db).upsert_block(request.model_dump(exclude_unset=True), block_id=block_id)
    db.commit()
    db.refresh(block)
    return FlexSubscriptionService._block_item(block)


@router.get("/price/{level}")
def flex_price(level: int):
    if level < 1 or level > 10:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Level must be 1–10")
    return {"level": level, "price_rub": price_for_level(level)}


@router.post("/checkout")
def create_flex_checkout(
    request: FlexLevelRequest,
    http_request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.core.config import settings
    from app.services.country_service import CountryService
    from app.services.legal_consent_service import consent_required
    from app.services.tbank_service import get_tbank_service
    from app.services.yookassa_service import get_yookassa_service

    if consent_required(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "LEGAL_CONSENT_REQUIRED",
                "message": "Примите документы перед оплатой",
            },
        )
    level = int(request.level)
    amount = float(price_for_level(level))
    country_code = current_user.country_code or CountryService.get_country_from_request(
        http_request
    )
    if not current_user.country_code:
        current_user.country_code = country_code
        db.commit()
    provider = CountryService.get_payment_provider_for_country(country_code)
    if provider == "none":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "PAYMENTS_UNAVAILABLE",
                "message": "Оплата подписок временно недоступна",
            },
        )
    success_url = f"{settings.FRONTEND_URL}/subscription/success"
    fail_url = f"{settings.FRONTEND_URL}/subscription/cancel"
    description = f"Гибкая подписка · уровень {level} ({int(amount)} ₽/мес)"
    extra = {"flex_level": str(level)}
    if provider == "tbank":
        tbank = get_tbank_service()
        if not tbank.enabled:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "T-Bank unavailable")
        result = tbank.create_payment(
            user_id=current_user.id,
            amount=amount,
            plan="monthly",
            description=description,
            success_url=success_url,
            fail_url=fail_url,
            product="flex",
            metadata_extra=extra,
        )
        return {
            "payment_id": result["payment_id"],
            "url": result["confirmation_url"],
            "provider": "sbp",
            "currency": "RUB",
            "level": level,
            "amount": amount,
        }
    if provider == "yookassa":
        yookassa = get_yookassa_service()
        if not yookassa.enabled:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "YooKassa unavailable")
        result = yookassa.create_payment(
            user_id=current_user.id,
            user_email=current_user.email,
            amount=amount,
            plan="monthly",
            description=description,
            return_url=success_url,
            product="flex",
            metadata_extra=extra,
        )
        return {
            "payment_id": result.get("payment_id") or result.get("id"),
            "url": result.get("confirmation_url") or result.get("url"),
            "provider": "yookassa",
            "currency": "RUB",
            "level": level,
            "amount": amount,
        }
    raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Payments unavailable")
