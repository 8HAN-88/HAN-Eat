"""
Сервис для работы с подписками H.A.N. Plus
"""
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional
from app.models.user import User
from app.models.subscription import Subscription


class SubscriptionService:
    """Сервис для управления подписками"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def get_user_subscription(self, user_id: int) -> Optional[Subscription]:
        """Получить активную подписку пользователя"""
        subscription = self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active",
            Subscription.expires_at > datetime.utcnow()
        ).order_by(Subscription.created_at.desc()).first()
        
        return subscription
    
    def is_user_plus(self, user_id: int) -> bool:
        """Проверить, является ли пользователь Plus подписчиком"""
        subscription = self.get_user_subscription(user_id)
        if not subscription:
            return False
        
        # Проверяем, не истекла ли подписка
        if subscription.expires_at and subscription.expires_at < datetime.utcnow():
            # Обновляем статус
            subscription.status = "expired"
            user = self.db.query(User).filter(User.id == user_id).first()
            if user:
                user.subscription_type = "free"
            self.db.commit()
            return False
        
        return True
    
    def create_subscription(
        self,
        user_id: int,
        plan: str,  # monthly | yearly
        payment_provider: str,
        payment_provider_subscription_id: str,
        amount: float,
        currency: str = "USD",
        stripe_subscription_id: Optional[str] = None
    ) -> Subscription:
        """Создать новую подписку"""
        # Отменяем предыдущие активные подписки
        active_subscriptions = self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active"
        ).all()
        
        for sub in active_subscriptions:
            sub.status = "cancelled"
            sub.cancelled_at = datetime.utcnow()
        
        # Вычисляем дату окончания
        expires_at = datetime.utcnow()
        if plan == "monthly":
            expires_at += timedelta(days=30)
        elif plan == "yearly":
            expires_at += timedelta(days=365)
        
        # Используем stripe_subscription_id если передан
        provider_sub_id = stripe_subscription_id or payment_provider_subscription_id
        
        # Создаем новую подписку
        subscription = Subscription(
            user_id=user_id,
            plan=plan,
            status="active",
            payment_provider=payment_provider,
            payment_provider_subscription_id=provider_sub_id,
            amount=amount,
            currency=currency,
            expires_at=expires_at,
            auto_renew=True
        )
        
        # Обновляем пользователя
        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            user.subscription_type = "plus"
            user.subscription_expires_at = expires_at
        
        self.db.add(subscription)
        self.db.commit()
        self.db.refresh(subscription)
        
        return subscription
    
    def cancel_subscription(
        self,
        user_id: int,
        subscription_id: Optional[int] = None
    ) -> bool:
        """Отменить подписку"""
        if subscription_id:
            subscription = self.db.query(Subscription).filter(
                Subscription.id == subscription_id,
                Subscription.user_id == user_id
            ).first()
        else:
            subscription = self.get_user_subscription(user_id)
        
        if not subscription:
            return False
        
        subscription.status = "cancelled"
        subscription.cancelled_at = datetime.utcnow()
        subscription.auto_renew = False
        
        # Обновляем пользователя (подписка остается до expires_at)
        user = self.db.query(User).filter(User.id == user_id).first()
        if user:
            # Не меняем subscription_type сразу, чтобы пользователь мог использовать до expires_at
            pass
        
        self.db.commit()
        return True
    
    def renew_subscription(self, subscription_id: int) -> bool:
        """Продлить подписку (вызывается платежной системой)"""
        subscription = self.db.query(Subscription).filter(
            Subscription.id == subscription_id
        ).first()
        
        if not subscription or subscription.status != "active":
            return False
        
        # Вычисляем новую дату окончания
        if subscription.plan == "monthly":
            subscription.expires_at += timedelta(days=30)
        elif subscription.plan == "yearly":
            subscription.expires_at += timedelta(days=365)
        
        # Обновляем пользователя
        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_expires_at = subscription.expires_at
        
        self.db.commit()
        return True
    
    def expire_subscription(self, subscription_id: int) -> bool:
        """Истечение подписки (вызывается периодической задачей)"""
        subscription = self.db.query(Subscription).filter(
            Subscription.id == subscription_id
        ).first()
        
        if not subscription:
            return False
        
        subscription.status = "expired"
        
        # Обновляем пользователя
        user = self.db.query(User).filter(User.id == subscription.user_id).first()
        if user:
            user.subscription_type = "free"
            user.subscription_expires_at = None
        
        self.db.commit()
        return True

