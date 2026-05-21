"""
Модель подписки H.A.N. Plus
"""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean, Numeric
from sqlalchemy.sql import func
from app.core.database import Base


class Subscription(Base):
    __tablename__ = "subscriptions"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    plan = Column(String(20), nullable=False)  # monthly | yearly
    product = Column(String(20), nullable=False, default="pro")  # ai | creator | pro
    status = Column(String(20), nullable=False, index=True)  # active | cancelled | expired | pending | trial
    payment_provider = Column(String(20), nullable=True)  # stripe | paypal | apple | google
    payment_provider_subscription_id = Column(String(255), nullable=True, index=True)  # ID подписки в платежной системе
    amount = Column(Numeric(10, 2), nullable=False)  # Сумма подписки
    currency = Column(String(3), default="USD")  # Валюта
    started_at = Column(DateTime, server_default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=True, index=True)
    cancelled_at = Column(DateTime, nullable=True)
    auto_renew = Column(Boolean, default=True)
    receipt_url = Column(String(512), nullable=True)
    refund_status = Column(String(20), nullable=False, default="none")  # none | requested | refunded | rejected
    refunded_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

