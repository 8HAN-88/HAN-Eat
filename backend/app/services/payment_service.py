"""
Сервис для работы с платежами через Stripe
"""
import os
import logging
from typing import Optional, Dict, Any
from app.core.config import settings

logger = logging.getLogger(__name__)

# Stripe SDK
STRIPE_AVAILABLE = False
try:
    import stripe
    STRIPE_AVAILABLE = True
except ImportError:
    STRIPE_AVAILABLE = False
    logger.warning("stripe not installed. Payment features will be disabled.")


class PaymentService:
    """Сервис для работы с платежами через Stripe"""
    
    def __init__(self):
        self.enabled = False
        self._initialize_stripe()
    
    def _initialize_stripe(self):
        """Инициализировать Stripe"""
        if not STRIPE_AVAILABLE:
            logger.warning("Stripe SDK not available")
            return
        
        if not settings.STRIPE_ENABLED:
            logger.info("Stripe disabled in settings")
            return
        
        if not settings.STRIPE_SECRET_KEY:
            logger.warning("Stripe enabled but STRIPE_SECRET_KEY not set")
            return
        
        try:
            stripe.api_key = settings.STRIPE_SECRET_KEY
            self.enabled = True
            logger.info("Stripe initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Stripe: {e}")
            self.enabled = False
    
    def create_checkout_session(
        self,
        user_id: int,
        user_email: str,
        plan: str,  # monthly | yearly
        success_url: Optional[str] = None,
        cancel_url: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Создать Stripe Checkout Session для подписки
        
        Args:
            user_id: ID пользователя
            user_email: Email пользователя
            plan: План подписки (monthly | yearly)
            success_url: URL для редиректа после успешной оплаты
            cancel_url: URL для редиректа при отмене
            
        Returns:
            Словарь с session_id и url для редиректа
        """
        if not self.enabled or not STRIPE_AVAILABLE:
            raise ValueError("Stripe is not enabled or not available")
        
        # Определяем price_id в зависимости от плана
        if plan == "monthly":
            price_id = settings.STRIPE_PRICE_ID_MONTHLY
        elif plan == "yearly":
            price_id = settings.STRIPE_PRICE_ID_YEARLY
        else:
            raise ValueError(f"Invalid plan: {plan}. Must be 'monthly' or 'yearly'")
        
        if not price_id:
            raise ValueError(f"Stripe price ID not configured for plan: {plan}")
        
        # URLs для редиректа
        if not success_url:
            success_url = f"{settings.FRONTEND_URL}/subscription/success?session_id={{CHECKOUT_SESSION_ID}}"
        if not cancel_url:
            cancel_url = f"{settings.FRONTEND_URL}/subscription/cancel"
        
        try:
            # Создаем checkout session
            session = stripe.checkout.Session.create(
                customer_email=user_email,
                payment_method_types=['card'],
                line_items=[{
                    'price': price_id,
                    'quantity': 1,
                }],
                mode='subscription',
                success_url=success_url,
                cancel_url=cancel_url,
                metadata={
                    'user_id': str(user_id),
                    'plan': plan,
                },
                subscription_data={
                    'metadata': {
                        'user_id': str(user_id),
                        'plan': plan,
                    }
                },
                allow_promotion_codes=True,  # Разрешаем промокоды
            )
            
            logger.info(f"Created Stripe checkout session {session.id} for user {user_id}")
            
            return {
                "session_id": session.id,
                "url": session.url,
                "customer_email": user_email,
            }
            
        except stripe.error.StripeError as e:
            logger.error(f"Stripe error creating checkout session: {e}")
            raise ValueError(f"Failed to create checkout session: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error creating checkout session: {e}")
            raise
    
    def get_subscription(self, subscription_id: str) -> Optional[Dict[str, Any]]:
        """
        Получить информацию о подписке из Stripe
        
        Args:
            subscription_id: ID подписки в Stripe
            
        Returns:
            Информация о подписке или None
        """
        if not self.enabled or not STRIPE_AVAILABLE:
            return None
        
        try:
            subscription = stripe.Subscription.retrieve(subscription_id)
            return {
                "id": subscription.id,
                "status": subscription.status,
                "customer": subscription.customer,
                "current_period_start": subscription.current_period_start,
                "current_period_end": subscription.current_period_end,
                "cancel_at_period_end": subscription.cancel_at_period_end,
                "metadata": subscription.metadata,
            }
        except stripe.error.StripeError as e:
            logger.error(f"Stripe error retrieving subscription: {e}")
            return None
    
    def cancel_subscription(self, subscription_id: str, immediately: bool = False) -> bool:
        """
        Отменить подписку в Stripe
        
        Args:
            subscription_id: ID подписки в Stripe
            immediately: Если True, отменить сразу, иначе в конце периода
            
        Returns:
            True если успешно, False в противном случае
        """
        if not self.enabled or not STRIPE_AVAILABLE:
            return False
        
        try:
            if immediately:
                # Отменить сразу
                stripe.Subscription.delete(subscription_id)
            else:
                # Отменить в конце периода
                stripe.Subscription.modify(
                    subscription_id,
                    cancel_at_period_end=True
                )
            
            logger.info(f"Cancelled Stripe subscription {subscription_id}")
            return True
            
        except stripe.error.StripeError as e:
            logger.error(f"Stripe error cancelling subscription: {e}")
            return False
    
    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        """
        Проверить подпись webhook от Stripe
        
        Args:
            payload: Тело запроса (bytes)
            signature: Заголовок Stripe-Signature
            
        Returns:
            True если подпись валидна, False в противном случае
        """
        if not self.enabled or not STRIPE_AVAILABLE:
            return False
        
        if not settings.STRIPE_WEBHOOK_SECRET:
            logger.warning("STRIPE_WEBHOOK_SECRET not set, cannot verify webhook")
            return False
        
        try:
            stripe.Webhook.construct_event(
                payload,
                signature,
                settings.STRIPE_WEBHOOK_SECRET
            )
            return True
        except ValueError as e:
            logger.error(f"Invalid payload in webhook: {e}")
            return False
        except stripe.error.SignatureVerificationError as e:
            logger.error(f"Invalid signature in webhook: {e}")
            return False
    
    def get_subscription_prices(self) -> Dict[str, Any]:
        """
        Получить информацию о ценах подписок из Stripe
        
        Returns:
            Словарь с ценами для monthly и yearly планов
        """
        if not self.enabled or not STRIPE_AVAILABLE:
            # Возвращаем дефолтные цены, если Stripe не настроен
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
                }
            }
        
        try:
            prices = {}
            
            # Получаем информацию о месячной подписке
            if settings.STRIPE_PRICE_ID_MONTHLY:
                try:
                    price_monthly = stripe.Price.retrieve(settings.STRIPE_PRICE_ID_MONTHLY)
                    prices["monthly"] = {
                        "price": price_monthly.unit_amount / 100.0,  # Stripe хранит цены в центах
                        "currency": price_monthly.currency.upper(),
                        "price_id": price_monthly.id,
                        "interval": price_monthly.recurring.interval if price_monthly.recurring else "month"
                    }
                except stripe.error.StripeError as e:
                    logger.error(f"Error retrieving monthly price: {e}")
                    prices["monthly"] = {
                        "price": 2.99,
                        "currency": "USD",
                        "price_id": settings.STRIPE_PRICE_ID_MONTHLY,
                        "interval": "month"
                    }
            else:
                prices["monthly"] = {
                    "price": 2.99,
                    "currency": "USD",
                    "price_id": None,
                    "interval": "month"
                }
            
            # Получаем информацию о годовой подписке
            if settings.STRIPE_PRICE_ID_YEARLY:
                try:
                    price_yearly = stripe.Price.retrieve(settings.STRIPE_PRICE_ID_YEARLY)
                    prices["yearly"] = {
                        "price": price_yearly.unit_amount / 100.0,  # Stripe хранит цены в центах
                        "currency": price_yearly.currency.upper(),
                        "price_id": price_yearly.id,
                        "interval": price_yearly.recurring.interval if price_yearly.recurring else "year"
                    }
                except stripe.error.StripeError as e:
                    logger.error(f"Error retrieving yearly price: {e}")
                    prices["yearly"] = {
                        "price": 29.99,
                        "currency": "USD",
                        "price_id": settings.STRIPE_PRICE_ID_YEARLY,
                        "interval": "year"
                    }
            else:
                prices["yearly"] = {
                    "price": 29.99,
                    "currency": "USD",
                    "price_id": None,
                    "interval": "year"
                }
            
            return prices
            
        except Exception as e:
            logger.error(f"Error getting subscription prices: {e}")
            # Возвращаем дефолтные цены при ошибке
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
                }
            }
    
    def handle_webhook_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Обработать событие webhook от Stripe
        
        Args:
            event: Событие от Stripe
            
        Returns:
            Результат обработки
        """
        event_type = event.get('type')
        event_data = event.get('data', {}).get('object', {})
        
        logger.info(f"Processing Stripe webhook event: {event_type}")
        
        result = {
            "processed": False,
            "event_type": event_type,
            "message": ""
        }
        
        if event_type == 'checkout.session.completed':
            # Пользователь успешно оплатил подписку
            session = event_data
            subscription_id = session.get('subscription')
            metadata = session.get('metadata', {})
            user_id = int(metadata.get('user_id', 0))
            plan = metadata.get('plan', 'monthly')
            
            if subscription_id and user_id:
                result["processed"] = True
                result["action"] = "create_subscription"
                result["user_id"] = user_id
                result["subscription_id"] = subscription_id
                result["plan"] = plan
                result["message"] = f"Checkout completed for user {user_id}"
            
        elif event_type == 'customer.subscription.created':
            # Подписка создана
            subscription = event_data
            subscription_id = subscription.get('id')
            metadata = subscription.get('metadata', {})
            user_id = int(metadata.get('user_id', 0))
            
            if subscription_id and user_id:
                result["processed"] = True
                result["action"] = "subscription_created"
                result["user_id"] = user_id
                result["subscription_id"] = subscription_id
                result["message"] = f"Subscription created for user {user_id}"
            
        elif event_type == 'customer.subscription.updated':
            # Подписка обновлена (например, продлена)
            subscription = event_data
            subscription_id = subscription.get('id')
            status = subscription.get('status')
            
            if subscription_id:
                result["processed"] = True
                result["action"] = "subscription_updated"
                result["subscription_id"] = subscription_id
                result["status"] = status
                result["message"] = f"Subscription {subscription_id} updated to {status}"
            
        elif event_type == 'customer.subscription.deleted':
            # Подписка отменена
            subscription = event_data
            subscription_id = subscription.get('id')
            
            if subscription_id:
                result["processed"] = True
                result["action"] = "subscription_deleted"
                result["subscription_id"] = subscription_id
                result["message"] = f"Subscription {subscription_id} deleted"
            
        elif event_type == 'invoice.payment_succeeded':
            # Успешная оплата инвойса (продление подписки)
            invoice = event_data
            subscription_id = invoice.get('subscription')
            
            if subscription_id:
                result["processed"] = True
                result["action"] = "payment_succeeded"
                result["subscription_id"] = subscription_id
                result["message"] = f"Payment succeeded for subscription {subscription_id}"
            
        elif event_type == 'invoice.payment_failed':
            # Неудачная оплата инвойса
            invoice = event_data
            subscription_id = invoice.get('subscription')
            
            if subscription_id:
                result["processed"] = True
                result["action"] = "payment_failed"
                result["subscription_id"] = subscription_id
                result["message"] = f"Payment failed for subscription {subscription_id}"
        
        return result


# Глобальный экземпляр сервиса
_payment_service: Optional[PaymentService] = None


def get_payment_service() -> PaymentService:
    """Получить глобальный экземпляр PaymentService"""
    global _payment_service
    if _payment_service is None:
        _payment_service = PaymentService()
    return _payment_service

