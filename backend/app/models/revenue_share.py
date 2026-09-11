"""Рефералка и доля с рекламы / подписки."""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class RevenueShareLedger(Base):
    __tablename__ = "revenue_share_ledger"
    __table_args__ = (
        UniqueConstraint(
            "source",
            "reference_type",
            "reference_id",
            "role",
            name="uq_revenue_share_ref_role",
        ),
    )

    id = Column(Integer, primary_key=True)
    beneficiary_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role = Column(String(16), nullable=False, index=True)
    source = Column(String(20), nullable=False, index=True)
    subject_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    referrer_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    extra_ads = Column(Boolean, nullable=False, default=False)
    gross_kopecks = Column(Integer, nullable=False, default=0)
    net_kopecks = Column(Integer, nullable=False, default=0)
    share_kopecks = Column(Integer, nullable=False, default=0)
    status = Column(String(16), nullable=False, default="pending", index=True)
    available_at = Column(DateTime, nullable=True, index=True)
    reference_type = Column(String(32), nullable=False)
    reference_id = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
