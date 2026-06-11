"""
Т-Банк (Tinkoff Acquiring API v2): СБП и рекуррентные списания.
Документация: https://www.tbank.ru/kassa/dev/
"""
from __future__ import annotations

import hashlib
import logging
import re
import uuid
from typing import Any, Dict, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_ORDER_ID_RE = re.compile(r"^HE(\d+)-[a-f0-9]+$", re.I)
_EXCLUDE_TOKEN_KEYS = frozenset(
    {"Token", "Receipt", "DATA", "Shops", "Receipts", "Items"}
)


class TBankService:
    """Приём платежей через интернет-эквайринг Т-Банка."""

    def __init__(self) -> None:
        self.enabled = bool(
            settings.TBANK_ENABLED
            and settings.TBANK_TERMINAL_KEY
            and settings.TBANK_PASSWORD
        )
        self.terminal_key = settings.TBANK_TERMINAL_KEY
        self.password = settings.TBANK_PASSWORD
        self.api_url = (settings.TBANK_API_URL or "https://securepay.tinkoff.ru/v2").rstrip(
            "/"
        )

    @staticmethod
    def sbp_recurring_enabled() -> bool:
        return bool(settings.TBANK_ENABLED and settings.TBANK_SBP_RECURRING_ENABLED)

    @staticmethod
    def receipt_item_description(product: str, plan: str = "monthly") -> str:
        names = {"ai": "H.A.N. AI", "creator": "H.A.N. Creator", "pro": "H.A.N. Pro"}
        period = "1 мес." if plan == "monthly" else "1 год"
        return f"Подписка {names.get(product, product)} ({period})"

    @staticmethod
    def make_order_id(user_id: int) -> str:
        return f"HE{user_id}-{uuid.uuid4().hex[:12]}"

    @staticmethod
    def parse_user_id_from_order_id(order_id: str) -> Optional[int]:
        m = _ORDER_ID_RE.match((order_id or "").strip())
        if not m:
            return None
        try:
            return int(m.group(1))
        except (TypeError, ValueError):
            return None

    def _notification_url(self) -> str:
        base = (settings.API_PUBLIC_BASE_URL or "").rstrip("/")
        return f"{base}/api/v1/payments/webhook/tbank"

    def _make_token(self, params: Dict[str, Any]) -> str:
        token_params: Dict[str, Any] = {}
        for key, value in params.items():
            if key in _EXCLUDE_TOKEN_KEYS:
                continue
            if isinstance(value, (dict, list)):
                continue
            token_params[key] = value
        token_params["Password"] = self.password
        concat = "".join(str(token_params[k]) for k in sorted(token_params.keys()))
        return hashlib.sha256(concat.encode("utf-8")).hexdigest()

    def _request(self, method: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.enabled:
            raise ValueError("T-Bank is not enabled")
        body = {**payload, "TerminalKey": self.terminal_key}
        body["Token"] = self._make_token(body)
        url = f"{self.api_url}/{method}"
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(url, json=body)
            resp.raise_for_status()
            data = resp.json()
        if not data.get("Success"):
            msg = data.get("Message") or data.get("Details") or "T-Bank API error"
            raise ValueError(f"{method} failed: {msg}")
        return data

    @staticmethod
    def _data_dict(
        user_id: int,
        plan: str,
        product: str,
        metadata_extra: Optional[Dict[str, str]] = None,
    ) -> Dict[str, str]:
        data = {
            "QR": "true",
            "user_id": str(user_id),
            "plan": plan,
            "product": product,
        }
        if metadata_extra:
            for k, v in metadata_extra.items():
                data[str(k)] = str(v)
        return data

    @staticmethod
    def _parse_data_field(raw: Any) -> Dict[str, str]:
        if isinstance(raw, dict):
            return {str(k): str(v) for k, v in raw.items()}
        return {}

    def create_payment(
        self,
        user_id: int,
        amount: float,
        plan: str,
        description: str,
        success_url: str,
        fail_url: str,
        product: str = "pro",
        metadata_extra: Optional[Dict[str, str]] = None,
        *,
        recurrent: Optional[bool] = None,
    ) -> Dict[str, Any]:
        """Создать платёж СБП (QR) с опциональной привязкой для рекуррента."""
        should_recur = (
            recurrent
            if recurrent is not None
            else self.sbp_recurring_enabled()
        )
        order_id = self.make_order_id(user_id)
        payload: Dict[str, Any] = {
            "Amount": int(round(amount * 100)),
            "OrderId": order_id,
            "Description": (description or self.receipt_item_description(product, plan))[
                :250
            ],
            "SuccessURL": success_url,
            "FailURL": fail_url,
            "NotificationURL": self._notification_url(),
            "PayType": "O",
            "DATA": self._data_dict(user_id, plan, product, metadata_extra),
        }
        if should_recur:
            payload["Recurrent"] = "Y"
            payload["CustomerKey"] = str(user_id)

        data = self._request("Init", payload)
        payment_url = data.get("PaymentURL") or data.get("PaymentUrl")
        if not payment_url:
            raise ValueError("T-Bank Init: missing PaymentURL")
        return {
            "payment_id": str(data.get("PaymentId")),
            "confirmation_url": payment_url,
            "order_id": order_id,
            "status": data.get("Status"),
            "amount": amount,
            "currency": "RUB",
        }

    def get_payment_state(self, payment_id: str) -> Optional[Dict[str, Any]]:
        if not self.enabled:
            return None
        try:
            data = self._request("GetState", {"PaymentId": int(payment_id)})
        except Exception as e:
            logger.error("T-Bank GetState error: %s", e)
            return None
        status = (data.get("Status") or "").upper()
        amount_kop = int(data.get("Amount") or 0)
        meta = self._parse_data_field(data.get("Data"))
        order_id = data.get("OrderId") or ""
        user_id = int(meta.get("user_id") or 0) if meta.get("user_id") else None
        if not user_id:
            user_id = self.parse_user_id_from_order_id(order_id)
        return {
            "id": str(data.get("PaymentId") or payment_id),
            "payment_id": str(data.get("PaymentId") or payment_id),
            "status": status,
            "paid": status in ("CONFIRMED", "AUTHORIZED"),
            "amount": amount_kop / 100.0,
            "currency": "RUB",
            "order_id": order_id,
            "metadata": meta,
            "user_id": user_id,
            "rebill_id": data.get("RebillId"),
            "receipt_url": None,
        }

    def charge_recurrent(
        self,
        payment_id: str,
        rebill_id: str,
    ) -> Dict[str, Any]:
        """Безакцептное списание по сохранённому RebillId (после Init)."""
        data = self._request(
            "Charge",
            {
                "PaymentId": int(payment_id),
                "RebillId": rebill_id,
            },
        )
        status = (data.get("Status") or "").upper()
        return {
            "payment_id": str(data.get("PaymentId") or payment_id),
            "status": status,
            "paid": status in ("CONFIRMED", "AUTHORIZED"),
        }

    def create_autopayment(
        self,
        user_id: int,
        user_email: str,  # noqa: ARG002 — для совместимости с YooKassa
        amount: float,
        plan: str,
        product: str,
        rebill_id: str,
        *,
        description: Optional[str] = None,
        metadata_extra: Optional[Dict[str, str]] = None,
        success_url: Optional[str] = None,
        fail_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Рекуррент: Init + Charge по RebillId."""
        desc = description or self.receipt_item_description(product, plan)
        init = self.create_payment(
            user_id=user_id,
            amount=amount,
            plan=plan,
            description=desc,
            success_url=success_url or f"{settings.FRONTEND_URL}/subscription/success",
            fail_url=fail_url or f"{settings.FRONTEND_URL}/subscription/cancel",
            product=product,
            metadata_extra=metadata_extra,
            recurrent=False,
        )
        charge = self.charge_recurrent(init["payment_id"], rebill_id)
        return {
            "payment_id": init["payment_id"],
            "status": charge.get("status"),
            "paid": charge.get("paid", False),
            "amount": amount,
            "currency": "RUB",
        }

    def verify_notification_token(self, payload: Dict[str, Any]) -> bool:
        incoming = payload.get("Token")
        if not incoming:
            return False
        expected = self._make_token(payload)
        return str(incoming).lower() == expected.lower()

    def parse_notification(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        status = (payload.get("Status") or "").upper()
        success = payload.get("Success")
        if isinstance(success, str):
            success = success.lower() in ("true", "1", "yes")
        payment_id = str(payload.get("PaymentId") or "")
        meta = self._parse_data_field(payload.get("Data"))
        order_id = payload.get("OrderId") or ""
        user_id = int(meta.get("user_id") or 0) if meta.get("user_id") else None
        if not user_id:
            user_id = self.parse_user_id_from_order_id(order_id)
        amount_kop = int(payload.get("Amount") or 0)
        return {
            "processed": True,
            "event_type": status,
            "payment_id": payment_id,
            "paid": bool(success) and status == "CONFIRMED",
            "status": status,
            "amount": amount_kop / 100.0 if amount_kop else None,
            "metadata": meta,
            "user_id": user_id,
            "rebill_id": payload.get("RebillId"),
            "action": "payment_confirmed" if status == "CONFIRMED" and success else None,
        }

    def cancel_payment(self, payment_id: str, amount_kopecks: Optional[int] = None) -> Dict[str, Any]:
        body: Dict[str, Any] = {"PaymentId": int(payment_id)}
        if amount_kopecks is not None:
            body["Amount"] = amount_kopecks
        return self._request("Cancel", body)


_tbank_service: Optional[TBankService] = None


def get_tbank_service() -> TBankService:
    global _tbank_service
    if _tbank_service is None:
        _tbank_service = TBankService()
    return _tbank_service
