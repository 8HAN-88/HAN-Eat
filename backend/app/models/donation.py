"""
Модель донатов (поддержка авторов)
"""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Index
from sqlalchemy.sql import func
from app.core.database import Base


class Donation(Base):
    __tablename__ = "donations"

    id = Column(Integer, primary_key=True, index=True)

    # Кто отправил
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    # Кому отправили (автор / владелец канала)
    recipient_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Канал, в котором был сделан донат (опционально)
    channel_id = Column(Integer, ForeignKey("channels.id", ondelete="SET NULL"), nullable=True, index=True)

    # Пост, под которым был сделан донат (опционально)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="SET NULL"), nullable=True, index=True)

    # Сумма в Stars
    amount_stars = Column(Integer, nullable=False)

    # Сообщение от донатера (опционально)
    message = Column(Text, nullable=True)

    # Статус транзакции
    status = Column(String(24), nullable=False, default="completed", index=True)  # completed | refunded | failed

    created_at = Column(DateTime, server_default=func.now(), nullable=False, index=True)

    # Индексы для быстрых выборок
    __table_args__ = (
        Index("idx_donations_recipient_created", "recipient_id", "created_at"),
        Index("idx_donations_sender_created", "sender_id", "created_at"),
    )
