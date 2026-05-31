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
from app.services.yookassa_service import get_yookassa_service
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

_TIER_LABELS = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro", "free": "Free"}


def _tier_label(tier: Optional[str]) -> str:
    if not tier:
        return "тариф"
    return _TIER_LABELS.get(str(tier).lower(), str(tier))


class CreateCheckoutSessionRequest(BaseModel):
    plan: str = "monthly"  # monthly | yearly
    product: str = "pro"  # ai | creator | pro
    success_url: Optional[str] = None
    cancel_url: Optional[str] = None


class CreatePaymentRequest(BaseModel):
    plan: str  # monthly | yearly
    success_url: Optional[str] = None


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
    provider: str  # "stripe" | "yookassa" | "sbp" (sbp = ЮKassa, только СБП)
    currency: str = "USD"
    payment_method: Optional[str] = None


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
    - Россия, Беларусь, Казахстан → ЮKassa (СБП, карты)
    - Другие страны → пока не поддерживается (можно добавить Stripe позже)
    
    Возвращает URL для редиректа пользователя на страницу оплаты
    """
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
    
    if request.plan not in ["monthly", "yearly"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Plan must be 'monthly' or 'yearly'",
        )

    product = (request.product or "pro").strip().lower()
    if product not in ("ai", "creator", "pro"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Product must be 'ai', 'creator', or 'pro'",
        )

    subscription_service = SubscriptionService(db)
    estimate = subscription_service.estimate_upgrade_charge(
        current_user.id, product, request.plan
    )
    amount = float(estimate["amount_due"])

    try:
        if provider == "yookassa":
            # Используем ЮKassa для России и стран СНГ
            yookassa_service = get_yookassa_service()
            
            if not yookassa_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (YooKassa) is not available"
                )
            
            tier_names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
            description = f"Подписка {tier_names.get(product, product)} (месяц)"
            if estimate.get("is_upgrade"):
                description += (
                    f", апгрейд с {_tier_label(estimate.get('from_tier'))}, "
                    f"скидка {estimate.get('credit_rub', 0):.0f} ₽"
                )

            receipt_line = yookassa_service.receipt_item_description(product, request.plan)
            if estimate.get("is_upgrade"):
                receipt_line += f", апгрейд −{estimate.get('credit_rub', 0):.0f} ₽"

            metadata_extra = {}
            if estimate.get("is_upgrade"):
                metadata_extra = {
                    "is_upgrade": "1",
                    "upgrade_from": str(estimate.get("from_tier") or ""),
                    "credit_rub": f"{estimate.get('credit_rub', 0):.2f}",
                    "full_price_rub": f"{estimate.get('full_price', amount):.2f}",
                }

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
                existing = subscription_service.get_subscription_by_provider_payment_id(
                    payment_id, "yookassa"
                )
                if existing:
                    subscription_service.refresh_receipt_url(existing)
                    logger.info(
                        "YooKassa payment %s already linked to subscription %s",
                        payment_id,
                        existing.id,
                    )
                else:
                    payment_info = yookassa_service.get_payment_status(payment_id)

                    if not payment_info or not payment_info.get("paid"):
                        logger.warning(
                            "YooKassa webhook: payment %s not paid or not found",
                            payment_id,
                        )
                    else:
                        metadata = payment_info.get("metadata") or {}
                        try:
                            user_id = int(metadata.get("user_id") or 0)
                        except (TypeError, ValueError):
                            user_id = 0
                        plan = metadata.get("plan") or "monthly"
                        product = metadata.get("product") or "pro"

                        if not user_id:
                            logger.error(
                                "YooKassa payment %s missing user_id in verified metadata",
                                payment_id,
                            )
                        else:
                            amount = float(payment_info.get("amount") or 0)
                            if amount <= 0:
                                amount = float(
                                    subscription_service.price_for_product(product, plan)
                                )

                            subscription = subscription_service.create_subscription(
                                user_id=user_id,
                                plan=plan,
                                product=product,
                                payment_provider="yookassa",
                                payment_provider_subscription_id=payment_id,
                                amount=amount,
                                currency=payment_info.get("currency") or "RUB",
                                platform="yookassa",
                                receipt_url=payment_info.get("receipt_url"),
                            )

                            pay_meta = payment_info.get("metadata") or {}
                            AnalyticsService(db).log_event(
                                event_type="subscription_payment_success",
                                entity_type="subscription",
                                entity_id=subscription.id,
                                user_id=user_id,
                                metadata={
                                    "product": product,
                                    "plan": plan,
                                    "amount": amount,
                                    "provider": "yookassa",
                                    "is_upgrade": pay_meta.get("is_upgrade") == "1",
                                },
                            )

                            logger.info(
                                "Subscription created for user %s: %s",
                                user_id,
                                subscription.id,
                            )
                            try:
                                from app.core.redis_client import get_redis
                                from app.services.feed_service import FeedService

                                FeedService(db, get_redis()).invalidate_feed_cache(
                                    user_id
                                )
                            except Exception as inv_err:
                                logger.warning(
                                    "Feed cache invalidate after payment: %s",
                                    inv_err,
                                )

        elif result.get("action") == "payment_canceled":
            payment_id = result.get("payment_id")
            if payment_id:
                logger.info("YooKassa payment canceled: %s", payment_id)
        
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
    
    if provider == "yookassa":
        prices_provider = (
            "sbp"
            if (settings.YOOKASSA_PAYMENT_METHOD or "sbp").strip().lower() == "sbp"
            else "yookassa"
        )
        return {
            "provider": prices_provider,
            "payment_method": settings.YOOKASSA_PAYMENT_METHOD,
            "country": country_code,
            "currency": "RUB",
            "trial_days": settings.SUBSCRIPTION_TRIAL_DAYS,
            "tiers": {
                "ai": {
                    "name": "H.A.N. AI",
                    "monthly": {
                        "price": settings.AI_MONTHLY_PRICE_RUB,
                        "currency": "RUB",
                        "interval": "month",
                    },
                    "trial_eligible": True,
                    "benefits": [
                        "Больше AI-сканов",
                        "Расширенный анализ питания",
                        "Планы питания",
                        "Умные рекомендации",
                    ],
                },
                "creator": {
                    "name": "H.A.N. Creator",
                    "monthly": {
                        "price": settings.CREATOR_MONTHLY_PRICE_RUB,
                        "currency": "RUB",
                        "interval": "month",
                    },
                    "trial_eligible": False,
                    "benefits": [
                        "Аналитика канала",
                        "Продвижение контента",
                        "Инструменты для авторов",
                        "Оформление канала",
                    ],
                },
                "pro": {
                    "name": "H.A.N. Pro",
                    "monthly": {
                        "price": settings.PRO_MONTHLY_PRICE_RUB,
                        "currency": "RUB",
                        "interval": "month",
                    },
                    "trial_eligible": True,
                    "recommended": True,
                    "benefits": ["полный доступ ко всем функциям"],
                },
            },
            # legacy
            "monthly": {
                "price": settings.PRO_MONTHLY_PRICE_RUB,
                "currency": "RUB",
                "interval": "month",
            },
            "yearly": {
                "price": settings.PLUS_YEARLY_PRICE_RUB,
                "currency": "RUB",
                "interval": "year",
            },
        }
    
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
    product_names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
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
    if s.payment_provider != "yookassa":
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
    Публичная проверка готовности ЮKassa (без секретов).
    Для деплоя: убедитесь, что issues пуст и webhook URL доступен из интернета.
    """
    from app.services.yookassa_service import get_yookassa_service

    issues = collect_payments_issues()
    yk = get_yookassa_service()
    base = settings.API_PUBLIC_BASE_URL.rstrip("/")
    return {
        "yookassa_enabled": settings.YOOKASSA_ENABLED,
        "yookassa_ready": yk.enabled,
        "app_env": settings.APP_ENV,
        "frontend_url": settings.FRONTEND_URL,
        "webhook_url": f"{base}/api/v1/payments/webhook/yookassa",
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
    """Провести возврат через ЮKassa (только админ)."""
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

    product_names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
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

