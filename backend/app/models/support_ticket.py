"""
Модель обращения в поддержку
"""
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.sql import func
from app.core.database import Base


class SupportTicket(Base):
    __tablename__ = "support_tickets"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type = Column(String(50), nullable=False, index=True)  # cancel_subscription | technical_issue | billing | other
    subject = Column(String(255), nullable=False)
    message = Column(Text, nullable=False)
    status = Column(String(20), default="open", index=True)  # open | in_progress | resolved | closed
    resolved_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)  # Кто обработал
    resolution_comment = Column(Text, nullable=True)  # Комментарий при обработке
    created_at = Column(DateTime, server_default=func.now(), index=True)
    resolved_at = Column(DateTime, nullable=True)
    closed_at = Column(DateTime, nullable=True)
    
    # Дополнительные данные для автоматической обработки
    related_entity_type = Column(String(20), nullable=True)  # subscription | post | user
    related_entity_id = Column(Integer, nullable=True)  # ID связанной сущности

