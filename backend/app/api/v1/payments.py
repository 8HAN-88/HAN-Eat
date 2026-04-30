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
from app.api.dependencies import get_current_user_required
from app.models.user import User
from app.services.payment_service import get_payment_service
from app.services.yookassa_service import get_yookassa_service
from app.services.country_service import CountryService
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)

router = APIRouter()


class CreateCheckoutSessionRequest(BaseModel):
    plan: str  # monthly | yearly
    success_url: Optional[str] = None
    cancel_url: Optional[str] = None


class CreatePaymentRequest(BaseModel):
    plan: str  # monthly | yearly
    success_url: Optional[str] = None


class CheckoutSessionResponse(BaseModel):
    session_id: Optional[str] = None
    payment_id: Optional[str] = None
    url: str
    customer_email: str
    provider: str  # "stripe" | "yookassa"
    currency: str = "USD"


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
    
    # Валидация плана
    if request.plan not in ["monthly", "yearly"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Plan must be 'monthly' or 'yearly'"
        )
    
    # Цены в рублях для России
    prices_rub = {
        "monthly": 299.0,  # 299 рублей
        "yearly": 2499.0,  # 2499 рублей
    }
    
    try:
        if provider == "yookassa":
            # Используем ЮKassa для России и стран СНГ
            yookassa_service = get_yookassa_service()
            
            if not yookassa_service.enabled:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Payment service (YooKassa) is not available"
                )
            
            amount = prices_rub[request.plan]
            description = f"Подписка H.A.N. Plus ({'месячная' if request.plan == 'monthly' else 'годовая'})"
            
            result = yookassa_service.create_payment(
                user_id=current_user.id,
                user_email=current_user.email,
                amount=amount,
                plan=request.plan,
                description=description,
                return_url=request.success_url or f"{settings.FRONTEND_URL}/subscription/success"
            )
            
            return CheckoutSessionResponse(
                payment_id=result["payment_id"],
                url=result["confirmation_url"],
                customer_email=current_user.email,
                provider="yookassa",
                currency="RUB"
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
        if result.get("action") == "payment_succeeded":
            # Создаем подписку в БД
            user_id = result.get("user_id")
            payment_id = result.get("payment_id")
            plan = result.get("plan", "monthly")
            
            if user_id and payment_id:
                # Получаем информацию о платеже
                payment_info = yookassa_service.get_payment_status(payment_id)
                
                if payment_info and payment_info.get("paid"):
                    # Цены в рублях
                    amount = 299.0 if plan == "monthly" else 2499.0
                    
                    subscription = subscription_service.create_subscription(
                        user_id=user_id,
                        plan=plan,
                        payment_provider="yookassa",
                        payment_provider_subscription_id=payment_id,
                        amount=amount,
                        currency="RUB"
                    )
                    
                    logger.info(f"Subscription created for user {user_id}: {subscription.id}")
        
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
            detail=f"Failed to process webhook: {str(e)}"
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
                        stripe_subscription_id=subscription_id
                    )
                    
                    logger.info(f"Subscription created for user {user_id}: {subscription.id}")
        
        elif result.get("action") == "subscription_updated":
            # Обновляем подписку (например, продление)
            subscription_id = result.get("subscription_id")
            status_str = result.get("status")
            
            if subscription_id:
                # Находим подписку в БД
                from app.models.subscription import Subscription
                subscription = db.query(Subscription).filter(
                    Subscription.payment_provider_subscription_id == subscription_id
                ).first()
                
                if subscription:
                    if status_str == "active":
                        # Продлеваем подписку
                        subscription_service.renew_subscription(subscription.id)
                    elif status_str in ["canceled", "unpaid", "past_due"]:
                        # Отменяем подписку
                        subscription.status = "cancelled"
                        db.commit()
        
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
            # Успешная оплата (продление)
            subscription_id = result.get("subscription_id")
            
            if subscription_id:
                from app.models.subscription import Subscription
                subscription = db.query(Subscription).filter(
                    Subscription.payment_provider_subscription_id == subscription_id
                ).first()
                
                if subscription:
                    subscription_service.renew_subscription(subscription.id)
        
        elif result.get("action") == "payment_failed":
            # Неудачная оплата
            subscription_id = result.get("subscription_id")
            
            if subscription_id:
                from app.models.subscription import Subscription
                subscription = db.query(Subscription).filter(
                    Subscription.payment_provider_subscription_id == subscription_id
                ).first()
                
                if subscription:
                    # Можно отправить уведомление пользователю
                    logger.warning(f"Payment failed for subscription {subscription_id}")
                    # TODO: Отправить уведомление пользователю
        
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
    current_user: Optional[User] = Depends(get_current_user_required),
    db: Session = Depends(get_db)
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
    
    # Цены в рублях для России
    if provider == "yookassa":
        return {
            "monthly": {
                "price": 299.0,
                "currency": "RUB",
                "price_id": None,
                "interval": "month"
            },
            "yearly": {
                "price": 2499.0,
                "currency": "RUB",
                "price_id": None,
                "interval": "year"
            },
            "provider": "yookassa",
            "country": country_code
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

