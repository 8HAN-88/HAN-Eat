"""
Сервис для работы с платежами через ЮKassa (Яндекс.Касса) с поддержкой СБП
"""
import os
import logging
import hashlib
import hmac
from typing import Optional, Dict, Any
from datetime import datetime
from app.core.config import settings

logger = logging.getLogger(__name__)

# ЮKassa SDK
YOOKASSA_AVAILABLE = False
try:
    import yookassa
    from yookassa import Configuration, Payment
    YOOKASSA_AVAILABLE = True
except ImportError:
    YOOKASSA_AVAILABLE = False
    logger.warning("yookassa not installed. YooKassa payment features will be disabled.")


class YooKassaService:
    """Сервис для работы с платежами через ЮKassa (СБП, карты, электронные кошельки)"""
    
    def __init__(self):
        self.enabled = False
        self._initialize_yookassa()
    
    def _initialize_yookassa(self):
        """Инициализировать ЮKassa"""
        if not YOOKASSA_AVAILABLE:
            logger.warning("YooKassa SDK not available")
            return
        
        if not settings.YOOKASSA_ENABLED:
            logger.info("YooKassa disabled in settings")
            return
        
        if not settings.YOOKASSA_SHOP_ID or not settings.YOOKASSA_SECRET_KEY:
            logger.warning("YooKassa enabled but credentials not set")
            return
        
        try:
            Configuration.account_id = settings.YOOKASSA_SHOP_ID
            Configuration.secret_key = settings.YOOKASSA_SECRET_KEY
            self.enabled = True
            logger.info("YooKassa initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize YooKassa: {e}")
            self.enabled = False
    
    @staticmethod
    def receipt_item_description(product: str, plan: str = "monthly") -> str:
        """Короткое наименование для чека 54-ФЗ (до 128 символов)."""
        names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
        period = "1 мес." if plan == "monthly" else "1 год"
        return f"Подписка {names.get(product, product)} ({period})"

    def create_payment(
        self,
        user_id: int,
        user_email: str,
        amount: float,
        plan: str,  # monthly | yearly
        description: str = "Подписка H.A.N. Pro",
        return_url: Optional[str] = None,
        product: str = "pro",
        receipt_description: Optional[str] = None,
        metadata_extra: Optional[Dict[str, str]] = None,
        payment_method: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Создать платеж через ЮKassa с поддержкой СБП
        
        Args:
            user_id: ID пользователя
            user_email: Email пользователя
            amount: Сумма платежа в рублях
            plan: План подписки (monthly | yearly)
            description: Описание платежа
            return_url: URL для возврата после оплаты
            
        Returns:
            Словарь с payment_id и confirmation_url
        """
        if not self.enabled or not YOOKASSA_AVAILABLE:
            raise ValueError("YooKassa is not enabled or not available")
        
        if not return_url:
            return_url = f"{settings.FRONTEND_URL}/subscription/success"
        
        try:
            # Создаем платеж
            # Idempotence key для предотвращения дублирования платежей
            import uuid
            idempotence_key = str(uuid.uuid4())
            
            payment_dict = {
                "amount": {
                    "value": f"{amount:.2f}",
                    "currency": "RUB"
                },
                "confirmation": {
                    "type": "redirect",
                    "return_url": return_url
                },
                "capture": True,
                "description": description,
                "metadata": {
                    "user_id": str(user_id),
                    "plan": plan,
                    "product": product,
                    **(metadata_extra or {}),
                },
                "receipt": {
                    "customer": {
                        "email": user_email
                    },
                    "items": [
                        {
                            "description": (
                                receipt_description
                                or self.receipt_item_description(product, plan)
                            )[:128],
                            "quantity": "1.00",
                            "amount": {
                                "value": f"{amount:.2f}",
                                "currency": "RUB"
                            },
                            "vat_code": 1,
                            "payment_mode": "full_payment",
                            "payment_subject": "service",
                        }
                    ]
                }
            }
            if method == "sbp":
                payment_dict["payment_method_data"] = {"type": "sbp"}
            elif method not in ("", "any", "all"):
                payment_dict["payment_method_data"] = {"type": method}

            payment = Payment.create(payment_dict, idempotence_key)

            logger.info(
                "Created YooKassa payment %s for user %s (method=%s)",
                payment.id,
                user_id,
                method,
            )
            
            return {
                "payment_id": payment.id,
                "confirmation_url": payment.confirmation.confirmation_url,
                "status": payment.status,
                "amount": amount,
                "currency": "RUB"
            }
            
        except Exception as e:
            logger.error(f"YooKassa error creating payment: {e}")
            raise ValueError(f"Failed to create payment: {str(e)}")
    
    @staticmethod
    def extract_receipt_url(payment: Any) -> Optional[str]:
        """URL фискального чека из объекта Payment ЮKassa (если уже зарегистрирован)."""
        if payment is None:
            return None
        for attr in ("receipt_ofd_url", "fiscal_receipt_url"):
            url = getattr(payment, attr, None)
            if url:
                return str(url)
        reg = getattr(payment, "receipt_registration", None)
        if reg:
            for attr in ("receipt_ofd_url", "fiscal_receipt_url"):
                url = getattr(reg, attr, None)
                if url:
                    return str(url)
        return None

    def create_refund(
        self,
        payment_id: str,
        amount: float,
        currency: str = "RUB",
        reason: str = "Возврат по запросу пользователя",
    ) -> Dict[str, Any]:
        """Создать возврат в ЮKassa (полный или частичный)."""
        if not self.enabled or not YOOKASSA_AVAILABLE:
            raise ValueError("YooKassa is not enabled or not available")
        import uuid

        from yookassa import Refund

        refund = Refund.create(
            {
                "payment_id": payment_id,
                "amount": {"value": f"{amount:.2f}", "currency": currency},
                "description": reason[:250],
            },
            str(uuid.uuid4()),
        )
        return {
            "refund_id": refund.id,
            "status": refund.status,
            "amount": amount,
            "currency": currency,
        }

    def get_payment_status(self, payment_id: str) -> Optional[Dict[str, Any]]:
        """
        Получить статус платежа
        
        Args:
            payment_id: ID платежа в ЮKassa
            
        Returns:
            Информация о платеже или None
        """
        if not self.enabled or not YOOKASSA_AVAILABLE:
            return None
        
        try:
            payment = Payment.find_one(payment_id)
            return {
                "id": payment.id,
                "status": payment.status,
                "paid": payment.paid,
                "amount": float(payment.amount.value),
                "currency": payment.amount.currency,
                "metadata": payment.metadata,
                "receipt_url": self.extract_receipt_url(payment),
                "created_at": payment.created_at.isoformat() if payment.created_at else None,
            }
        except Exception as e:
            logger.error(f"YooKassa error retrieving payment: {e}")
            return None
    
    def verify_webhook_signature(self, payment_id: str, event_type: str, signature: str) -> bool:
        """
        Проверить подпись webhook от ЮKassa
        
        Args:
            payment_id: ID платежа
            event_type: Тип события
            signature: Подпись из заголовка
            
        Returns:
            True если подпись валидна
        """
        if not settings.YOOKASSA_SECRET_KEY:
            return False
        
        try:
            # Формируем строку для проверки
            data_string = f"{payment_id}|{event_type}"
            expected_signature = hmac.new(
                settings.YOOKASSA_SECRET_KEY.encode(),
                data_string.encode(),
                hashlib.sha256
            ).hexdigest()
            
            return hmac.compare_digest(signature, expected_signature)
        except Exception as e:
            logger.error(f"Error verifying YooKassa webhook signature: {e}")
            return False
    
    def handle_webhook_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Обработать событие webhook от ЮKassa
        
        Args:
            event: Событие от ЮKassa
            
        Returns:
            Результат обработки
        """
        event_type = event.get('event')
        payment_data = event.get('object', {})
        
        logger.info(f"Processing YooKassa webhook event: {event_type}")
        
        result = {
            "processed": False,
            "event_type": event_type,
            "message": ""
        }
        
        if event_type == 'payment.succeeded':
            # Доверяем только payment_id; user/plan/product — из API Payment.find_one().
            payment_id = payment_data.get('id')
            if payment_id:
                result["processed"] = True
                result["action"] = "payment_succeeded"
                result["payment_id"] = payment_id
                result["message"] = f"Payment succeeded: {payment_id}"
        
        elif event_type == 'payment.canceled':
            # Платеж отменен
            payment_id = payment_data.get('id')
            if payment_id:
                result["processed"] = True
                result["action"] = "payment_canceled"
                result["payment_id"] = payment_id
                result["message"] = f"Payment {payment_id} canceled"

        elif event_type == 'refund.succeeded':
            refund_id = payment_data.get('id')
            payment_id = payment_data.get('payment_id')
            if payment_id:
                result["processed"] = True
                result["action"] = "refund_succeeded"
                result["payment_id"] = payment_id
                result["refund_id"] = refund_id
                result["message"] = f"Refund succeeded for payment {payment_id}"
        
        return result


# Глобальный экземпляр сервиса
_yookassa_service: Optional[YooKassaService] = None


def get_yookassa_service() -> YooKassaService:
    """Получить глобальный экземпляр YooKassaService"""
    global _yookassa_service
    if _yookassa_service is None:
        _yookassa_service = YooKassaService()
    return _yookassa_service

