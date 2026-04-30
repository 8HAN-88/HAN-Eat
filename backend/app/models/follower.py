"""
Модель подписок
"""
from sqlalchemy import Column, Integer, DateTime, CheckConstraint
from sqlalchemy.sql import func
from app.core.database import Base


class Follower(Base):
    __tablename__ = "followers"
    
    id = Column(Integer, primary_key=True, index=True)
    follower_id = Column(Integer, nullable=False, index=True)
    followee_id = Column(Integer, nullable=False, index=True)
    created_at = Column(DateTime, server_default=func.now())
    
    __table_args__ = (
        CheckConstraint('follower_id != followee_id', name='check_no_self_follow'),
    )

