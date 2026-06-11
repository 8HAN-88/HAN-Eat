"""
Сервис платежей через ЮKassa: СБП с сохранением способа оплаты и автопродлением.
"""
import hashlib
import hmac
import logging
import uuid
from typing import Any, Dict, Optional

from app.core.config import settings

logger = logging.getLogger(__name__)

YOOKASSA_AVAILABLE = False
try:
    import yookassa
    from yookassa import Configuration, Payment

    YOOKASSA_AVAILABLE = True
except ImportError:
    yookassa = None
    Payment = None
    logger.warning("yookassa not installed. YooKassa payment features will be disabled.")


class YooKassaService:
    """ЮKassa: приём СБП, привязка счёта, безакцептные списания по подписке."""

    def __init__(self):
        self.enabled = False
        self._initialize_yookassa()

    def _initialize_yookassa(self):
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
            logger.error("Failed to initialize YooKassa: %s", e)
            self.enabled = False

    @staticmethod
    def resolved_payment_method(payment_method: Optional[str] = None) -> str:
        return (payment_method or settings.YOOKASSA_PAYMENT_METHOD or "sbp").strip().lower()

    @staticmethod
    def sbp_recurring_enabled() -> bool:
        if not settings.YOOKASSA_SBP_RECURRING_ENABLED:
            return False
        return YooKassaService.resolved_payment_method() == "sbp"

    @staticmethod
    def receipt_item_description(product: str, plan: str = "monthly") -> str:
        names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
        period = "1 мес." if plan == "monthly" else "1 год"
        return f"Подписка {names.get(product, product)} ({period})"

    @staticmethod
    def extract_payment_method_id(payment: Any) -> Optional[str]:
        pm = getattr(payment, "payment_method", None)
        if pm is None:
            return None
        pm_id = getattr(pm, "id", None)
        return str(pm_id) if pm_id else None

    @staticmethod
    def payment_method_saved(payment: Any) -> bool:
        pm = getattr(payment, "payment_method", None)
        return bool(getattr(pm, "saved", False)) if pm is not None else False

    def _build_receipt(
        self,
        user_email: str,
        amount: float,
        product: str,
        plan: str,
        receipt_description: Optional[str] = None,
    ) -> Dict[str, Any]:
        return {
            "customer": {"email": user_email},
            "items": [
                {
                    "description": (
                        receipt_description
                        or self.receipt_item_description(product, plan)
                    )[:128],
                    "quantity": "1.00",
                    "amount": {"value": f"{amount:.2f}", "currency": "RUB"},
                    "vat_code": 1,
                    "payment_mode": "full_payment",
                    "payment_subject": "service",
                }
            ],
        }

    def create_payment(
        self,
        user_id: int,
        user_email: str,
        amount: float,
        plan: str,
        description: str = "Подписка H.A.N. Pro",
        return_url: Optional[str] = None,
        product: str = "pro",
        receipt_description: Optional[str] = None,
        metadata_extra: Optional[Dict[str, str]] = None,
        payment_method: Optional[str] = None,
        *,
        save_payment_method: Optional[bool] = None,
    ) -> Dict[str, Any]:
        """Первый платёж СБП: redirect в банк + привязка счёта для автопродлений."""
        if not self.enabled or not YOOKASSA_AVAILABLE:
            raise ValueError("YooKassa is not enabled or not available")

        method = self.resolved_payment_method(payment_method)
        if not return_url:
            return_url = f"{settings.FRONTEND_URL}/subscription/success"

        should_save = save_payment_method
        if should_save is None:
            should_save = method == "sbp" and self.sbp_recurring_enabled()

        try:
            payment_dict: Dict[str, Any] = {
                "amount": {"value": f"{amount:.2f}", "currency": "RUB"},
                "confirmation": {"type": "redirect", "return_url": return_url},
                "capture": True,
                "description": description,
                "metadata": {
                    "user_id": str(user_id),
                    "plan": plan,
                    "product": product,
                    **(metadata_extra or {}),
                },
                "receipt": self._build_receipt(
                    user_email, amount, product, plan, receipt_description
                ),
            }
            if should_save:
                payment_dict["save_payment_method"] = True
            if method == "sbp":
                payment_dict["payment_method_data"] = {"type": "sbp"}
            elif method not in ("", "any", "all"):
                payment_dict["payment_method_data"] = {"type": method}

            payment = Payment.create(payment_dict, str(uuid.uuid4()))
            logger.info(
                "Created YooKassa payment %s for user %s (method=%s, save_pm=%s)",
                payment.id,
                user_id,
                method,
                should_save,
            )
            return {
                "payment_id": payment.id,
                "confirmation_url": payment.confirmation.confirmation_url,
                "status": payment.status,
                "amount": amount,
                "currency": "RUB",
            }
        except Exception as e:
            logger.error("YooKassa error creating payment: %s", e)
            raise ValueError(f"Failed to create payment: {str(e)}") from e

    def create_autopayment(
        self,
        user_id: int,
        user_email: str,
        amount: float,
        plan: str,
        product: str,
        payment_method_id: str,
        *,
        description: Optional[str] = None,
        receipt_description: Optional[str] = None,
        metadata_extra: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """Безакцептное списание по сохранённому СБП (без redirect в банк)."""
        if not self.enabled or not YOOKASSA_AVAILABLE:
            raise ValueError("YooKassa is not enabled or not available")
        if not payment_method_id:
            raise ValueError("payment_method_id is required for autopayment")

        desc = description or self.receipt_item_description(product, plan)
        try:
            payment_dict: Dict[str, Any] = {
                "amount": {"value": f"{amount:.2f}", "currency": "RUB"},
                "capture": True,
                "payment_method_id": payment_method_id,
                "description": desc,
                "metadata": {
                    "user_id": str(user_id),
                    "plan": plan,
                    "product": product,
                    **(metadata_extra or {}),
                },
                "receipt": self._build_receipt(
                    user_email, amount, product, plan, receipt_description
                ),
            }
            payment = Payment.create(payment_dict, str(uuid.uuid4()))
            logger.info(
                "Created YooKassa autopayment %s for user %s (subscription renewal)",
                payment.id,
                user_id,
            )
            return {
                "payment_id": payment.id,
                "status": payment.status,
                "paid": bool(getattr(payment, "paid", False)),
                "amount": amount,
                "currency": "RUB",
            }
        except Exception as e:
            logger.error("YooKassa autopayment error: %s", e)
            raise ValueError(f"Failed to create autopayment: {str(e)}") from e

    def create_refund(
        self,
        payment_id: str,
        amount: float,
        currency: str = "RUB",
        reason: str = "Возврат по запросу пользователя",
    ) -> Dict[str, Any]:
        if not self.enabled or not YOOKASSA_AVAILABLE:
            raise ValueError("YooKassa is not enabled or not available")
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

    @staticmethod
    def extract_receipt_url(payment: Any) -> Optional[str]:
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

    def get_payment_status(self, payment_id: str) -> Optional[Dict[str, Any]]:
        if not self.enabled or not YOOKASSA_AVAILABLE:
            return None
        try:
            payment = Payment.find_one(payment_id)
            pm_id = self.extract_payment_method_id(payment)
            return {
                "id": payment.id,
                "status": payment.status,
                "paid": payment.paid,
                "amount": float(payment.amount.value),
                "currency": payment.amount.currency,
                "metadata": payment.metadata,
                "receipt_url": self.extract_receipt_url(payment),
                "payment_method_id": pm_id,
                "payment_method_saved": self.payment_method_saved(payment),
                "created_at": payment.created_at.isoformat() if payment.created_at else None,
            }
        except Exception as e:
            logger.error("YooKassa error retrieving payment: %s", e)
            return None

    def verify_webhook_signature(
        self, payment_id: str, event_type: str, signature: str
    ) -> bool:
        if not settings.YOOKASSA_SECRET_KEY:
            return False
        try:
            data_string = f"{payment_id}|{event_type}"
            expected_signature = hmac.new(
                settings.YOOKASSA_SECRET_KEY.encode(),
                data_string.encode(),
                hashlib.sha256,
            ).hexdigest()
            return hmac.compare_digest(signature, expected_signature)
        except Exception as e:
            logger.error("Error verifying YooKassa webhook signature: %s", e)
            return False

    def handle_webhook_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        event_type = event.get("event")
        payment_data = event.get("object", {})
        logger.info("Processing YooKassa webhook event: %s", event_type)

        result: Dict[str, Any] = {
            "processed": False,
            "event_type": event_type,
            "message": "",
        }

        if event_type == "payment.succeeded":
            payment_id = payment_data.get("id")
            if payment_id:
                result["processed"] = True
                result["action"] = "payment_succeeded"
                result["payment_id"] = payment_id
                result["message"] = f"Payment succeeded: {payment_id}"

        elif event_type == "payment.canceled":
            payment_id = payment_data.get("id")
            if payment_id:
                result["processed"] = True
                result["action"] = "payment_canceled"
                result["payment_id"] = payment_id
                result["message"] = f"Payment {payment_id} canceled"

        elif event_type == "refund.succeeded":
            payment_id = payment_data.get("payment_id")
            if payment_id:
                result["processed"] = True
                result["action"] = "refund_succeeded"
                result["payment_id"] = payment_id
                result["refund_id"] = payment_data.get("id")
                result["message"] = f"Refund succeeded for payment {payment_id}"

        return result


_yookassa_service: Optional[YooKassaService] = None


def get_yookassa_service() -> YooKassaService:
    global _yookassa_service
    if _yookassa_service is None:
        _yookassa_service = YooKassaService()
    return _yookassa_service
