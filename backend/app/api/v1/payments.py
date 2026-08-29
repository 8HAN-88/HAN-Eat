"""
API endpoints для платежей через Stripe
"""
from fastapi import APIRouter, Depends, HTTPException, status, Request, Header
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from typing import Optional
import logging

# Stripe SDK
try:
    import stripe
    STRIPE_AVAILABLE = True
except ImportError:
    STRIPE_AVAILABLE = False
    stripe = None

from app.core.database import get_db
from app.core.config import settings
from app.api.dependencies import (
    get_current_user,
    get_current_user_required,
    get_current_admin_required,
)
from app.models.user import User
from app.models.subscription import Subscription
from app.models.support_ticket import SupportTicket
from app.services.payment_service import get_payment_service
from app.services.ru_payment_provider import get_active_ru_gateway
from app.services.yookassa_service import get_yookassa_service
from app.services.tbank_service import get_tbank_service
from app.services.payment_success_handler import process_payment_succeeded
from app.services.country_service import CountryService
from app.services.subscription_service import SubscriptionService
from datetime import datetime, timedelta
from app.services.notification_service import NotificationService
from app.services.analytics_service import AnalyticsService
from app.services.subscription_notify import (
    notify_refund_approved,
    notify_refund_rejected,
    notify_refund_requested,
)
from app.core.payments_startup import collect_payments_issues

logger = logging.getLogger(__name__)

router = APIRouter()

_TIER_LABELS = {"ai": "HanWe AI", "creator": "HanWe Creator", "pro": "HanWe Pro", "free": "Free"}


def _tier_label(tier: Optional[str]) -> str:
    if not tier:
        return "тариф"
    return _TIER_LABELS.get(str(tier).lower(), str(tier))


def _ru_subscription_prices_response(
    *,
    country_code: Optional[str],
    prices_provider: str,
    payment_backend: str,
    payment_method: Optional[str],
    checkout_available: bool,
    checkout_message: Optional[str] = None,
) -> dict:
    """Каталог тарифов RU/BY/KZ (с ценами и флагом доступности оплаты)."""
    payload = {
        "provider": prices_provider,
        "payment_method": payment_method,
        "payment_backend": payment_backend,
        "country": country_code,
        "currency": "RUB",
        "trial_days": settings.SUBSCRIPTION_TRIAL_DAYS,
        "checkout_available": checkout_available,
        "model": "flex",
        "flex": {
            "base_price_rub": 39,
            "step_price_rub": 10,
            "max_level": 10,
            "formula": "39 + (level - 1) * 10",
        },
        "tiers": {},
        "monthly": {
            "price": 39,
            "currency": "RUB",
            "interval": "month",
        },
        "yearly": {
            "price": 390,
            "currency": "RUB",
            "interval": "year",
        },
    }
    if checkout_message:
        payload["checkout_message"] = checkout_message
    return payload


class CreateCheckoutSessionRequest(BaseModel):
    plan: str = "monthly"
    product: str = "flex"
    flex_level: Optional[int] = None
    success_url: Optional[str] = None
    cancel_url: Optional[str] = None


class CreatePaymentRequest(BaseModel):
    plan: str  # monthly | yearly
    success_url: Optional[str] = None


class CreateStarsCheckoutRequest(BaseModel):
    package_id: str
    success_url: Optional[str] = None
    cancel_url: Optional[str] = None


class RefundRequestBody(BaseModel):
    subscription_id: int
    reason: Optional[str] = None


class AdminRefundBody(BaseModel):
    subscription_id: int
    amount: Optional[float] = None
    reason: Optional[str] = "Возврат одобрен поддержкой"
    resolve_ticket: bool = True


class AdminRejectRefundBody(BaseModel):
    subscription_id: int
    comment: Optional[str] = "Возврат отклонён"
    resolve_ticket: bool = True


class CheckoutSessionResponse(BaseModel):
    session_id: Optional[str] = None
    payment_id: Optional[str] = None
    url: str
    customer_email: str
    provider: str  # "stripe" | "tbank" | "yookassa" | "sbp"
    currency: str = "USD"
    payment_method: Optional[str] = None


STAR_PACKAGES = {
    "stars_100": {"stars": 100, "price_rub": 99, "title": "100 звёзд"},
    "stars_500": {"stars": 500, "price_rub": 449, "title": "500 звёзд"},
    "stars_1200": {"stars": 1200, "price_rub": 990, "title": "1200 звёзд"},
}


@router.post("/stars/checkout", response_model=CheckoutSessionResponse)
async def create_stars_checkout(
    request: CreateStarsCheckoutRequest,
    http_request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.legal_consent_service import consent_required

    if consent_required(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "LEGAL_CONSENT_REQUIRED",
                "message": "Примите документы перед оплатой",
            },
        )
    package = STAR_PACKAGES.get(request.package_id)
    if not package:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unknown stars package")

    country_code = current_user.country_code or CountryService.get_country_from_request(http_request)
    if not current_user.country_code:
        current_user.country_code = country_code
        db.commit()
    provider = CountryService.get_payment_provider_for_country(country_code)
    if provider not in ("tbank", "yookassa"):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "PAYMENTS_UNAVAILABLE",
                "message": "Покупка звёзд временно доступна только через RU-платежи",
            },
        )

    amount = float(package["price_rub"])
    stars = int(package["stars"])
    description = f"HanWe Stars: {stars} звёзд"
    metadata_extra = {
        "package_id": request.package_id,
        "stars": str(stars),
    }
    success_url = request.success_url or f"{settings.FRONTEND_URL}/paid/success"
    fail_url = request.cancel_url or f"{settings.FRONTEND_URL}/paid/cancel"

    try:
        if provider == "tbank":
            tbank_service = get_tbank_service()
            if not tbank_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (T-Bank) is not available",
                )
            result = tbank_service.create_payment(
                user_id=current_user.id,
                amount=amount,
                plan=request.package_id,
                description=description,
                success_url=success_url,
                fail_url=fail_url,
                product="stars",
                metadata_extra=metadata_extra,
                recurrent=False,
            )
            checkout_provider = "sbp"
        else:
            yookassa_service = get_yookassa_service()
            if not yookassa_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (YooKassa) is not available",
                )
            result = yookassa_service.create_payment(
                user_id=current_user.id,
                user_email=current_user.email,
                amount=amount,
                plan=request.package_id,
                description=description,
                return_url=success_url,
                product="stars",
                receipt_description=description[:128],
                metadata_extra=metadata_extra,
                save_payment_method=False,
            )
            checkout_provider = (
                "sbp"
                if (settings.YOOKASSA_PAYMENT_METHOD or "sbp").strip().lower() == "sbp"
                else "yookassa"
            )

        AnalyticsService(db).log_event(
            event_type="stars_checkout_start",
            entity_type="user",
            entity_id=current_user.id,
            user_id=current_user.id,
            metadata={
                "package_id": request.package_id,
                "stars": stars,
                "amount": amount,
                "provider": provider,
            },
        )
        db.commit()
        return CheckoutSessionResponse(
            payment_id=result["payment_id"],
            url=result["confirmation_url"],
            customer_email=current_user.email,
            provider=checkout_provider,
            currency="RUB",
            payment_method="sbp" if checkout_provider == "sbp" else settings.YOOKASSA_PAYMENT_METHOD,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to create stars checkout: %s", e, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create stars checkout",
        )


@router.post("/checkout", response_model=CheckoutSessionResponse)
async def create_checkout_session(
    request: CreateCheckoutSessionRequest,
    http_request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db)
):
    """
    Создать платежную сессию для покупки подписки
    
    Автоматически определяет страну пользователя и выбирает платежный провайдер:
    - Россия, Беларусь, Казахстан → Т-Банк или ЮKassa (СБП)
    - Другие страны → пока не поддерживается (можно добавить Stripe позже)
    
    Возвращает URL для редиректа пользователя на страницу оплаты
    """
    from app.services.legal_consent_service import consent_required

    if consent_required(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "LEGAL_CONSENT_REQUIRED",
                "message": (
                    "Примите политику конфиденциальности и пользовательское "
                    "соглашение перед оплатой подписки"
                ),
            },
        )

    # Определяем страну пользователя
    country_code = current_user.country_code
    if not country_code:
        # Определяем по запросу, если не сохранено в профиле
        country_code = CountryService.get_country_from_request(http_request)
        # Сохраняем в профиль
        current_user.country_code = country_code
        db.commit()
    
    # Определяем платежный провайдер
    provider = CountryService.get_payment_provider_for_country(country_code)

    if provider == "none" and (country_code or "").upper() in ("RU", "BY", "KZ"):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "PAYMENTS_UNAVAILABLE",
                "message": (
                    "Оплата подписок временно недоступна. "
                    "Подключим после публикации приложения в App Store."
                ),
            },
        )
    
    if request.plan not in ["monthly", "yearly"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Plan must be 'monthly' or 'yearly'",
        )

    product = (request.product or "flex").strip().lower()
    if product in ("ai", "creator", "pro"):
        from app.services.flex_subscription_service import LEGACY_TIER_LEVELS, price_for_level

        mapped = LEGACY_TIER_LEVELS.get(product, 6)
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "code": "FLEX_SUBSCRIPTION_ONLY",
                "message": "Классические тарифы отключены. Оформите гибкую подписку.",
                "flex_level": mapped,
                "price_rub": price_for_level(mapped),
            },
        )
    if product != "flex":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Product must be 'flex'",
        )

    from app.services.flex_subscription_service import price_for_level

    subscription_service = SubscriptionService(db)
    flex_level = int(request.flex_level or 1)
    flex_level = max(1, min(10, flex_level))
    amount = float(price_for_level(flex_level))
    estimate = {
        "amount_due": amount,
        "full_price": amount,
        "is_upgrade": False,
        "credit_rub": 0,
        "from_tier": "flex",
    }

    try:
        if provider == "tbank":
            tbank_service = get_tbank_service()
            if not tbank_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (T-Bank) is not available",
                )

            description = f"Гибкая подписка · уровень {flex_level} ({int(amount)} ₽/мес)"
            if estimate.get("is_upgrade"):
                description += (
                    f", апгрейд с {_tier_label(estimate.get('from_tier'))}, "
                    f"скидка {estimate.get('credit_rub', 0):.0f} ₽"
                )

            receipt_line = tbank_service.receipt_item_description(product, request.plan)
            if estimate.get("is_upgrade"):
                receipt_line += f", апгрейд −{estimate.get('credit_rub', 0):.0f} ₽"

            metadata_extra = {"flex_level": str(flex_level)}
            if estimate.get("is_upgrade"):
                metadata_extra.update({
                    "is_upgrade": "1",
                    "upgrade_from": str(estimate.get("from_tier") or ""),
                    "credit_rub": f"{estimate.get('credit_rub', 0):.2f}",
                    "full_price_rub": f"{estimate.get('full_price', amount):.2f}",
                })

            success_url = (
                request.success_url or f"{settings.FRONTEND_URL}/subscription/success"
            )
            fail_url = request.cancel_url or f"{settings.FRONTEND_URL}/subscription/cancel"

            result = tbank_service.create_payment(
                user_id=current_user.id,
                amount=amount,
                plan=request.plan,
                description=description,
                success_url=success_url,
                fail_url=fail_url,
                product=product,
                metadata_extra=metadata_extra,
            )

            tier_before, active_before = subscription_service.effective_tier(
                current_user.id
            )
            AnalyticsService(db).log_event(
                event_type="subscription_checkout_start",
                entity_type="user",
                entity_id=current_user.id,
                user_id=current_user.id,
                metadata={
                    "product": product,
                    "plan": request.plan,
                    "amount": amount,
                    "provider": "tbank",
                    "upgrade_from": tier_before if active_before else "free",
                    "is_upgrade": bool(estimate.get("is_upgrade")),
                    "credit_rub": estimate.get("credit_rub", 0),
                    "full_price": estimate.get("full_price", amount),
                },
            )
            db.commit()

            return CheckoutSessionResponse(
                payment_id=result["payment_id"],
                url=result["confirmation_url"],
                customer_email=current_user.email,
                provider="sbp",
                currency="RUB",
                payment_method="sbp",
            )

        elif provider == "yookassa":
            yookassa_service = get_yookassa_service()
            
            if not yookassa_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (YooKassa) is not available"
                )
            
            description = f"Гибкая подписка · уровень {flex_level} ({int(amount)} ₽/мес)"
            if estimate.get("is_upgrade"):
                description += (
                    f", апгрейд с {_tier_label(estimate.get('from_tier'))}, "
                    f"скидка {estimate.get('credit_rub', 0):.0f} ₽"
                )

            receipt_line = yookassa_service.receipt_item_description(product, request.plan)
            if estimate.get("is_upgrade"):
                receipt_line += f", апгрейд −{estimate.get('credit_rub', 0):.0f} ₽"

            metadata_extra = {"flex_level": str(flex_level)}
            if estimate.get("is_upgrade"):
                metadata_extra.update({
                    "is_upgrade": "1",
                    "upgrade_from": str(estimate.get("from_tier") or ""),
                    "credit_rub": f"{estimate.get('credit_rub', 0):.2f}",
                    "full_price_rub": f"{estimate.get('full_price', amount):.2f}",
                })

            result = yookassa_service.create_payment(
                user_id=current_user.id,
                user_email=current_user.email,
                amount=amount,
                plan=request.plan,
                description=description,
                return_url=request.success_url or f"{settings.FRONTEND_URL}/subscription/success",
                product=product,
                receipt_description=receipt_line[:128],
                metadata_extra=metadata_extra,
            )

            tier_before, active_before = subscription_service.effective_tier(
                current_user.id
            )
            AnalyticsService(db).log_event(
                event_type="subscription_checkout_start",
                entity_type="user",
                entity_id=current_user.id,
                user_id=current_user.id,
                metadata={
                    "product": product,
                    "plan": request.plan,
                    "amount": amount,
                    "provider": "yookassa",
                    "upgrade_from": tier_before if active_before else "free",
                    "is_upgrade": bool(estimate.get("is_upgrade")),
                    "credit_rub": estimate.get("credit_rub", 0),
                    "full_price": estimate.get("full_price", amount),
                },
            )
            db.commit()

            checkout_provider = (
                "sbp"
                if (settings.YOOKASSA_PAYMENT_METHOD or "sbp").strip().lower() == "sbp"
                else "yookassa"
            )
            return CheckoutSessionResponse(
                payment_id=result["payment_id"],
                url=result["confirmation_url"],
                customer_email=current_user.email,
                provider=checkout_provider,
                currency="RUB",
                payment_method=settings.YOOKASSA_PAYMENT_METHOD,
            )
        
        elif provider == "stripe":
            # Stripe для западных стран (пока отключено)
            payment_service = get_payment_service()
            
            if not payment_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (Stripe) is not available"
                )
            
            result = payment_service.create_checkout_session(
                user_id=current_user.id,
                user_email=current_user.email,
                plan=request.plan,
                success_url=request.success_url,
                cancel_url=request.cancel_url
            )
            
            return CheckoutSessionResponse(
                session_id=result["session_id"],
                url=result["url"],
                customer_email=result["customer_email"],
                provider="stripe",
                currency="USD"
            )
        
        else:
            # Платежи не поддерживаются для этой страны
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Payment is not available for your country ({country_code}). Currently supported: Russia, Belarus, Kazakhstan."
            )
        
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating payment session: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create payment session"
        )


@router.post("/webhook/yookassa")
async def yookassa_webhook(
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Webhook endpoint для обработки событий от ЮKassa
    
    Обрабатывает события:
    - payment.succeeded: Платеж успешно завершен
    - payment.canceled: Платеж отменен
    """
    yookassa_service = get_yookassa_service()
    
    if not yookassa_service.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YooKassa service is not available"
        )
    
    try:
        event = await request.json()
    except Exception as e:
        logger.error(f"Invalid JSON in YooKassa webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook payload"
        )

    signature = (
        request.headers.get("X-YooKassa-Signature")
        or request.headers.get("X-Yookassa-Signature")
        or request.headers.get("X-Webhook-Signature")
        or ""
    )
    if settings.APP_ENV == "production" or settings.YOOKASSA_WEBHOOK_SIGNATURE_REQUIRED:
        if not yookassa_service.verify_webhook_event(event, signature):
            logger.warning("YooKassa webhook: invalid or missing signature")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid webhook signature",
            )
    
    # Обрабатываем событие
    result = yookassa_service.handle_webhook_event(event)
    
    # Выполняем действия на основе результата
    subscription_service = SubscriptionService(db)
    
    try:
        if result.get("action") == "refund_succeeded":
            payment_id = result.get("payment_id")
            sub = subscription_service.get_subscription_by_provider_payment_id(
                payment_id, "yookassa"
            )
            if sub and sub.refund_status != "refunded":
                sub.refund_status = "refunded"
                sub.refunded_at = datetime.utcnow()
                subscription_service.revoke_access_after_refund(sub)
                product = getattr(sub, "product", "pro") or "pro"
                notify_refund_approved(
                    db,
                    user_id=sub.user_id,
                    subscription_id=sub.id,
                    amount=float(sub.amount),
                    product=product,
                )
                try:
                    from app.core.redis_client import get_redis
                    from app.services.feed_service import FeedService

                    FeedService(db, get_redis()).invalidate_feed_cache(sub.user_id)
                except Exception as inv_err:
                    logger.warning(
                        "Feed cache invalidate after refund: %s", inv_err
                    )

        elif result.get("action") == "payment_succeeded":
            payment_id = result.get("payment_id")
            if not payment_id:
                logger.warning("YooKassa payment_succeeded without payment_id")
            else:
                info = yookassa_service.get_payment_status(payment_id)
                process_payment_succeeded(
                    db,
                    payment_provider="yookassa",
                    payment_id=payment_id,
                    payment_info=info or {},
                )
                try:
                    info = yookassa_service.get_payment_status(payment_id)
                    uid = int((info or {}).get("metadata", {}).get("user_id") or 0)
                    if uid:
                        from app.core.redis_client import get_redis
                        from app.services.feed_service import FeedService

                        FeedService(db, get_redis()).invalidate_feed_cache(uid)
                except Exception as inv_err:
                    logger.warning(
                        "Feed cache invalidate after payment: %s", inv_err
                    )

        elif result.get("action") == "payment_canceled":
            payment_id = result.get("payment_id")
            if payment_id:
                logger.info("YooKassa payment canceled: %s", payment_id)
                pending = (
                    db.query(Subscription)
                    .filter(Subscription.pending_renewal_payment_id == payment_id)
                    .first()
                )
                if pending:
                    subscription_service.clear_renewal_payment_pending(pending)
                    if pending.expires_at and pending.expires_at < datetime.utcnow():
                        subscription_service.disable_auto_renew_after_failed_payment(
                            pending
                        )
        
        db.commit()
        
        return {
            "success": True,
            "processed": result.get("processed", False),
            "message": result.get("message", "Event processed")
        }
        
    except Exception as e:
        logger.error(f"Error processing YooKassa webhook: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process webhook",
        )


@router.post("/webhook/tbank")
async def tbank_webhook(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Webhook Т-Банка (эквайринг v2): CONFIRMED — активация/продление подписки.
    """
    tbank_service = get_tbank_service()
    if not tbank_service.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="T-Bank service is not available",
        )

    try:
        payload = await request.json()
    except Exception as e:
        logger.error("Invalid JSON in T-Bank webhook: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook payload",
        )

    if not tbank_service.verify_notification_token(payload):
        logger.warning("T-Bank webhook: invalid Token signature")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid notification signature",
        )

    result = tbank_service.parse_notification(payload)
    subscription_service = SubscriptionService(db)

    try:
        if result.get("paid") and result.get("payment_id"):
            payment_id = result["payment_id"]
            info = tbank_service.get_payment_state(payment_id) or {
                "paid": True,
                "metadata": result.get("metadata") or {},
                "user_id": result.get("user_id"),
                "amount": result.get("amount"),
                "rebill_id": result.get("rebill_id"),
            }
            if result.get("rebill_id") and not info.get("rebill_id"):
                info["rebill_id"] = result.get("rebill_id")
            process_payment_succeeded(
                db,
                payment_provider="tbank",
                payment_id=payment_id,
                payment_info=info,
            )
            try:
                uid = int(
                    (info.get("metadata") or {}).get("user_id")
                    or info.get("user_id")
                    or 0
                )
                if uid:
                    from app.core.redis_client import get_redis
                    from app.services.feed_service import FeedService

                    FeedService(db, get_redis()).invalidate_feed_cache(uid)
            except Exception as inv_err:
                logger.warning("Feed cache invalidate after T-Bank payment: %s", inv_err)

        elif result.get("status") in ("CANCELED", "REJECTED", "REVERSED"):
            payment_id = result.get("payment_id")
            if payment_id:
                pending = (
                    db.query(Subscription)
                    .filter(Subscription.pending_renewal_payment_id == payment_id)
                    .first()
                )
                if pending:
                    subscription_service.clear_renewal_payment_pending(pending)
                    if pending.expires_at and pending.expires_at < datetime.utcnow():
                        subscription_service.disable_auto_renew_after_failed_payment(
                            pending
                        )

        db.commit()
        return {"success": True, "processed": result.get("processed", False)}

    except Exception as e:
        logger.error("Error processing T-Bank webhook: %s", e, exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process webhook",
        )


@router.post("/webhook")
@router.post("/webhook/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="stripe-signature"),
    db: Session = Depends(get_db)
):
    """
    Webhook endpoint для обработки событий от Stripe
    
    Обрабатывает события:
    - checkout.session.completed: Пользователь успешно оплатил
    - customer.subscription.created: Подписка создана
    - customer.subscription.updated: Подписка обновлена
    - customer.subscription.deleted: Подписка отменена
    - invoice.payment_succeeded: Успешная оплата (продление)
    - invoice.payment_failed: Неудачная оплата
    """
    payment_service = get_payment_service()
    
    if not payment_service.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Payment service is not available"
        )
    
    if not stripe_signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing stripe-signature header"
        )
    
    # Получаем тело запроса
    payload = await request.body()
    
    # Проверяем подпись
    if not payment_service.verify_webhook_signature(payload, stripe_signature):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook signature"
        )
    
    # Парсим событие
    if not STRIPE_AVAILABLE:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe SDK not available"
        )
    
    try:
        event = stripe.Webhook.construct_event(
            payload,
            stripe_signature,
            settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError as e:
        logger.error(f"Invalid payload in webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook payload"
        )
    except stripe.error.SignatureVerificationError as e:
        logger.error(f"Invalid signature in webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook signature"
        )
    
    # Обрабатываем событие
    result = payment_service.handle_webhook_event(event)
    
    # Выполняем действия на основе результата
    subscription_service = SubscriptionService(db)
    
    try:
        if result.get("action") == "create_subscription":
            # Создаем подписку в БД
            user_id = result.get("user_id")
            subscription_id = result.get("subscription_id")
            plan = result.get("plan", "monthly")
            
            if user_id and subscription_id:
                # Получаем информацию о подписке из Stripe
                subscription_info = payment_service.get_subscription(subscription_id)
                
                if subscription_info:
                    # Получаем реальную сумму из Stripe Subscription
                    stripe_period_end: Optional[datetime] = None
                    try:
                        import stripe
                        stripe_subscription = stripe.Subscription.retrieve(subscription_id)
                        # Получаем цену из первого item подписки
                        if stripe_subscription.items.data:
                            price = stripe_subscription.items.data[0].price
                            amount = price.unit_amount / 100.0 if price.unit_amount else 0.0
                            currency = price.currency.upper() if price.currency else "USD"
                        else:
                            # Fallback на дефолтные значения
                            amount = 2.99 if plan == "monthly" else 29.99
                            currency = "USD"
                        cpe = getattr(stripe_subscription, "current_period_end", None)
                        if cpe:
                            stripe_period_end = datetime.utcfromtimestamp(int(cpe))
                    except Exception as e:
                        logger.warning(f"Could not retrieve subscription details from Stripe: {e}")
                        # Fallback на дефолтные значения
                        amount = 2.99 if plan == "monthly" else 29.99
                        currency = "USD"
                    
                    subscription = subscription_service.create_subscription(
                        user_id=user_id,
                        plan=plan,
                        payment_provider="stripe",
                        payment_provider_subscription_id=subscription_id,
                        amount=amount,
                        currency=currency,
                        stripe_subscription_id=subscription_id,
                        expires_at=stripe_period_end,
                    )
                    
                    logger.info(f"Subscription created for user {user_id}: {subscription.id}")
        
        elif result.get("action") == "subscription_updated":
            # Синхронизируем конец периода и статус со Stripe (без слепого +30 дней)
            subscription_id = result.get("subscription_id")
            status_str = result.get("status")
            period_end_ts = result.get("current_period_end")
            
            if subscription_id:
                if period_end_ts is None:
                    info = payment_service.get_subscription(subscription_id)
                    if info and info.get("current_period_end"):
                        period_end_ts = info["current_period_end"]
                if period_end_ts is not None:
                    subscription_service.sync_subscription_period_by_provider_id(
                        subscription_id,
                        int(period_end_ts),
                        stripe_status=status_str,
                    )
                elif status_str in ("canceled", "unpaid", "past_due"):
                    from app.models.subscription import Subscription
                    subscription = db.query(Subscription).filter(
                        Subscription.payment_provider_subscription_id == subscription_id
                    ).first()
                    if subscription:
                        if status_str == "canceled":
                            subscription.status = "cancelled"
                            subscription.auto_renew = False
                        elif status_str in ("unpaid", "past_due"):
                            subscription.auto_renew = False
        
        elif result.get("action") == "subscription_deleted":
            # Отменяем подписку в БД
            subscription_id = result.get("subscription_id")
            
            if subscription_id:
                from app.models.subscription import Subscription
                subscription = db.query(Subscription).filter(
                    Subscription.payment_provider_subscription_id == subscription_id
                ).first()
                
                if subscription:
                    subscription_service.cancel_subscription(
                        subscription.user_id,
                        subscription.id
                    )
        
        elif result.get("action") == "payment_succeeded":
            # Успешная оплата: выравниваем expires_at по периоду инвойса / Stripe
            subscription_id = result.get("subscription_id")
            period_end_ts = result.get("period_end")
            
            if subscription_id:
                if period_end_ts is None:
                    info = payment_service.get_subscription(subscription_id)
                    if info and info.get("current_period_end"):
                        period_end_ts = info["current_period_end"]
                if period_end_ts is not None:
                    subscription_service.sync_subscription_period_by_provider_id(
                        subscription_id,
                        int(period_end_ts),
                        stripe_status=None,
                    )
        
        elif result.get("action") == "payment_failed":
            # Неудачная оплата
            subscription_id = result.get("subscription_id")
            
            if subscription_id:
                from app.models.subscription import Subscription
                subscription = db.query(Subscription).filter(
                    Subscription.payment_provider_subscription_id == subscription_id
                ).first()
                
                if subscription:
                    logger.warning(f"Payment failed for subscription {subscription_id}")
                    NotificationService(db).create_notification(
                        user_id=subscription.user_id,
                        type="system",
                        title="Не удалось списать оплату",
                        body="Проверьте способ оплаты или продлите подписку в разделе «Подписка».",
                        entity_type="subscription",
                        entity_id=subscription.id,
                        data={
                            "action": "payment_failed",
                            "payment_provider_subscription_id": subscription_id,
                        },
                    )

        db.commit()
        
        return {
            "success": True,
            "processed": result.get("processed", False),
            "message": result.get("message", "Event processed")
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook action: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process webhook: {str(e)}"
        )


@router.get("/prices")
async def get_subscription_prices(
    http_request: Request,
    current_user: Optional[User] = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Получить информацию о ценах подписок
    
    Возвращает цены в зависимости от страны пользователя:
    - Россия, Беларусь, Казахстан → цены в рублях (RUB)
    - Другие страны → цены в долларах (USD, пока не поддерживается)
    """
    # Определяем страну
    country_code = None
    if current_user and current_user.country_code:
        country_code = current_user.country_code
    else:
        country_code = CountryService.get_country_from_request(http_request)
    
    provider = CountryService.get_payment_provider_for_country(country_code)

    if provider == "none" and (country_code or "").upper() in ("RU", "BY", "KZ"):
        return _ru_subscription_prices_response(
            country_code=country_code,
            prices_provider="none",
            payment_backend="none",
            payment_method=None,
            checkout_available=False,
            checkout_message=(
                "Оплата появится после публикации в App Store. "
                "Пока доступен пробный период, если вы его ещё не использовали."
            ),
        )
    
    if provider in ("tbank", "yookassa"):
        if provider == "tbank":
            prices_provider = "sbp"
            payment_method = "sbp"
        else:
            prices_provider = (
                "sbp"
                if (settings.YOOKASSA_PAYMENT_METHOD or "sbp").strip().lower() == "sbp"
                else "yookassa"
            )
            payment_method = settings.YOOKASSA_PAYMENT_METHOD
        gateway = get_active_ru_gateway()
        checkout_available = gateway is not None and bool(getattr(gateway, "enabled", False))
        return _ru_subscription_prices_response(
            country_code=country_code,
            prices_provider=prices_provider,
            payment_backend=provider,
            payment_method=payment_method,
            checkout_available=checkout_available,
        )
    
    # Цены в долларах для Stripe (пока не поддерживается)
    elif provider == "stripe":
        payment_service = get_payment_service()
        if payment_service.enabled:
            try:
                prices = payment_service.get_subscription_prices()
                prices["provider"] = "stripe"
                prices["country"] = country_code
                return prices
            except Exception as e:
                logger.error(f"Error getting Stripe prices: {e}")
        
        # Fallback на дефолтные цены
        return {
            "monthly": {
                "price": 2.99,
                "currency": "USD",
                "price_id": None,
                "interval": "month"
            },
            "yearly": {
                "price": 29.99,
                "currency": "USD",
                "price_id": None,
                "interval": "year"
            },
            "provider": "stripe",
            "country": country_code
        }
    
    else:
        # Платежи не поддерживаются
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Payment is not available for your country ({country_code})"
        )


def _subscription_payment_dict(s: Subscription, svc: SubscriptionService) -> dict:
    product = getattr(s, "product", "pro") or "pro"
    product_names = {"ai": "HanWe AI", "creator": "HanWe Creator", "pro": "HanWe Pro"}
    refund_status = getattr(s, "refund_status", None) or "none"
    receipt_url = getattr(s, "receipt_url", None)
    if (
        not receipt_url
        and s.payment_provider == "yookassa"
        and s.payment_provider_subscription_id
        and not str(s.payment_provider_subscription_id).startswith("trial-")
    ):
        receipt_url = svc.refresh_receipt_url(s)
    return {
        "id": s.id,
        "product": product,
        "product_name": product_names.get(product, product),
        "plan": s.plan,
        "status": s.status,
        "amount": float(s.amount),
        "currency": s.currency,
        "payment_provider": s.payment_provider,
        "payment_id": s.payment_provider_subscription_id,
        "receipt_url": receipt_url,
        "refund_status": refund_status,
        "refunded_at": s.refunded_at.isoformat() if getattr(s, "refunded_at", None) else None,
        "can_request_refund": _can_request_refund(s),
        "started_at": s.started_at.isoformat() if s.started_at else None,
        "expires_at": s.expires_at.isoformat() if s.expires_at else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
    }


def _can_request_refund(s: Subscription) -> bool:
    refund_status = getattr(s, "refund_status", None) or "none"
    if refund_status not in ("none", "rejected"):
        return False
    if s.payment_provider not in ("yookassa", "tbank"):
        return False
    pid = s.payment_provider_subscription_id or ""
    if not pid or pid.startswith("trial-"):
        return False
    if s.status not in ("active", "cancelled", "expired"):
        return False
    started = s.started_at or s.created_at
    if not started:
        return False
    window = timedelta(days=settings.SUBSCRIPTION_REFUND_REQUEST_DAYS)
    return datetime.utcnow() - started <= window


@router.get("/readiness")
async def payments_readiness():
    """
    Публичная проверка готовности платежей (без секретов).
    """
    issues = collect_payments_issues()
    base = settings.API_PUBLIC_BASE_URL.rstrip("/")
    payload = {
        "tbank_enabled": settings.TBANK_ENABLED,
        "yookassa_enabled": settings.YOOKASSA_ENABLED,
        "app_env": settings.APP_ENV,
        "frontend_url": settings.FRONTEND_URL,
        "return_url_hint": f"{settings.FRONTEND_URL.rstrip('/')}/subscription/success",
        "tiers_rub": {
            "ai": settings.AI_MONTHLY_PRICE_RUB,
            "creator": settings.CREATOR_MONTHLY_PRICE_RUB,
            "pro": settings.PRO_MONTHLY_PRICE_RUB,
        },
        "refund_request_days": settings.SUBSCRIPTION_REFUND_REQUEST_DAYS,
        "issues": issues,
        "ready": len(issues) == 0,
    }
    if settings.TBANK_ENABLED:
        from app.services.tbank_service import get_tbank_service

        tb = get_tbank_service()
        payload["tbank_ready"] = tb.enabled
        payload["sbp_recurring"] = settings.TBANK_SBP_RECURRING_ENABLED
        payload["webhook_url"] = f"{base}/api/v1/payments/webhook/tbank"
    else:
        from app.services.yookassa_service import get_yookassa_service

        yk = get_yookassa_service()
        payload["yookassa_ready"] = yk.enabled
        payload["sbp_recurring"] = settings.YOOKASSA_SBP_RECURRING_ENABLED
        payload["webhook_url"] = f"{base}/api/v1/payments/webhook/yookassa"
    return payload


@router.get("/history")
async def get_payment_history(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
    limit: int = 20,
):
    """История оплат подписок (ЮKassa и др.) из таблицы subscriptions."""
    svc = SubscriptionService(db)
    rows = (
        db.query(Subscription)
        .filter(Subscription.user_id == current_user.id)
        .order_by(Subscription.created_at.desc())
        .limit(min(limit, 50))
        .all()
    )
    return {"payments": [_subscription_payment_dict(s, svc) for s in rows]}


@router.get("/admin/refund-queue")
async def admin_refund_queue(
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
    limit: int = 50,
):
    """Очередь запросов на возврат (только админ)."""
    rows = (
        db.query(Subscription)
        .filter(Subscription.refund_status == "requested")
        .order_by(Subscription.created_at.desc())
        .limit(min(limit, 100))
        .all()
    )
    svc = SubscriptionService(db)
    user_ids = {s.user_id for s in rows}
    users = {
        u.id: u
        for u in db.query(User).filter(User.id.in_(user_ids)).all()
    } if user_ids else {}

    items = []
    for s in rows:
        u = users.get(s.user_id)
        ticket = (
            db.query(SupportTicket)
            .filter(
                SupportTicket.related_entity_type == "subscription",
                SupportTicket.related_entity_id == s.id,
                SupportTicket.type == "billing_refund",
                SupportTicket.status.in_(["open", "in_progress"]),
            )
            .order_by(SupportTicket.created_at.desc())
            .first()
        )
        items.append(
            {
                **_subscription_payment_dict(s, svc),
                "user": {
                    "id": u.id,
                    "email": u.email,
                    "name": u.name,
                }
                if u
                else None,
                "ticket_id": ticket.id if ticket else None,
            }
        )
    return {"items": items, "total": len(items)}


@router.post("/admin/refund")
async def admin_process_refund(
    body: AdminRefundBody,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    """Провести возврат через Т-Банк или ЮKassa (только админ)."""
    sub = db.query(Subscription).filter(Subscription.id == body.subscription_id).first()
    if not sub:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found")
    if sub.refund_status == "refunded":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already refunded",
        )

    svc = SubscriptionService(db)
    try:
        if sub.payment_provider == "tbank":
            result = svc.apply_tbank_refund(
                sub,
                amount=body.amount,
                reason=body.reason or "Возврат одобрен поддержкой",
            )
        else:
            result = svc.apply_yookassa_refund(
                sub,
                amount=body.amount,
                reason=body.reason or "Возврат одобрен поддержкой",
            )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    if body.resolve_ticket:
        tickets = (
            db.query(SupportTicket)
            .filter(
                SupportTicket.related_entity_type == "subscription",
                SupportTicket.related_entity_id == sub.id,
                SupportTicket.type == "billing_refund",
                SupportTicket.status.in_(["open", "in_progress"]),
            )
            .all()
        )
        for ticket in tickets:
            ticket.status = "resolved"
            ticket.resolution_comment = body.reason or "Возврат выполнен"
            ticket.resolved_at = datetime.utcnow()
            ticket.resolved_by_user_id = current_user.id

    product = getattr(sub, "product", "pro") or "pro"
    notify_refund_approved(
        db,
        user_id=sub.user_id,
        subscription_id=sub.id,
        amount=float(result.get("amount") or sub.amount),
        product=product,
    )

    AnalyticsService(db).log_event(
        event_type="subscription_refund_processed",
        entity_type="subscription",
        entity_id=sub.id,
        user_id=sub.user_id,
        metadata={
            "admin_id": current_user.id,
            "amount": result.get("amount"),
            "refund_id": result.get("refund_id"),
        },
    )
    db.commit()

    return {
        "success": True,
        "subscription_id": sub.id,
        "refund_status": sub.refund_status,
        **result,
    }


@router.post("/admin/refund/reject")
async def admin_reject_refund(
    body: AdminRejectRefundBody,
    current_user: User = Depends(get_current_admin_required),
    db: Session = Depends(get_db),
):
    """Отклонить запрос на возврат (только админ)."""
    sub = db.query(Subscription).filter(Subscription.id == body.subscription_id).first()
    if not sub:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found")
    if sub.refund_status not in ("requested", "none"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot reject refund in status {sub.refund_status}",
        )

    sub.refund_status = "rejected"
    product = getattr(sub, "product", "pro") or "pro"
    if body.resolve_ticket:
        tickets = (
            db.query(SupportTicket)
            .filter(
                SupportTicket.related_entity_type == "subscription",
                SupportTicket.related_entity_id == sub.id,
                SupportTicket.type == "billing_refund",
                SupportTicket.status.in_(["open", "in_progress"]),
            )
            .all()
        )
        for ticket in tickets:
            ticket.status = "resolved"
            ticket.resolution_comment = body.comment or "Возврат отклонён"
            ticket.resolved_at = datetime.utcnow()
            ticket.resolved_by_user_id = current_user.id

    notify_refund_rejected(
        db,
        user_id=sub.user_id,
        subscription_id=sub.id,
        product=product,
        comment=body.comment,
    )
    db.commit()
    return {
        "success": True,
        "subscription_id": sub.id,
        "refund_status": sub.refund_status,
    }


@router.get("/{subscription_id}/receipt")
async def get_subscription_receipt(
    subscription_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Обновить и вернуть URL фискального чека ЮKassa."""
    sub = (
        db.query(Subscription)
        .filter(
            Subscription.id == subscription_id,
            Subscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payment not found")
    svc = SubscriptionService(db)
    url = svc.refresh_receipt_url(sub)
    return {"subscription_id": sub.id, "receipt_url": url}


@router.post("/refund-request")
async def request_payment_refund(
    body: RefundRequestBody,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Запрос возврата: создаёт тикет в поддержку и помечает подписку как requested."""
    sub = (
        db.query(Subscription)
        .filter(
            Subscription.id == body.subscription_id,
            Subscription.user_id == current_user.id,
        )
        .first()
    )
    if not sub:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payment not found")
    if not _can_request_refund(sub):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Refund is not available for this payment",
        )

    existing_ticket = (
        db.query(SupportTicket)
        .filter(
            SupportTicket.user_id == current_user.id,
            SupportTicket.type == "billing_refund",
            SupportTicket.related_entity_type == "subscription",
            SupportTicket.related_entity_id == sub.id,
            SupportTicket.status.in_(["open", "in_progress"]),
        )
        .first()
    )
    if existing_ticket:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Refund request already submitted",
        )

    product_names = {"ai": "HanWe AI", "creator": "HanWe Creator", "pro": "HanWe Pro"}
    product = getattr(sub, "product", "pro") or "pro"
    reason = (body.reason or "").strip() or "Прошу оформить возврат оплаты подписки."
    ticket = SupportTicket(
        user_id=current_user.id,
        type="billing_refund",
        subject=f"Возврат: {product_names.get(product, product)}",
        message=reason,
        status="open",
        related_entity_type="subscription",
        related_entity_id=sub.id,
    )
    sub.refund_status = "requested"
    db.add(ticket)
    db.flush()
    notify_refund_requested(
        db,
        user_id=current_user.id,
        subscription_id=sub.id,
        amount=float(sub.amount),
        product=product,
    )
    db.commit()
    db.refresh(ticket)

    AnalyticsService(db).log_event(
        event_type="subscription_refund_requested",
        entity_type="subscription",
        entity_id=sub.id,
        user_id=current_user.id,
        metadata={"amount": float(sub.amount), "product": product},
    )
    db.commit()

    return {
        "success": True,
        "ticket_id": ticket.id,
        "refund_status": sub.refund_status,
        "message": "Запрос на возврат отправлен. Поддержка свяжется с вами по email.",
    }

