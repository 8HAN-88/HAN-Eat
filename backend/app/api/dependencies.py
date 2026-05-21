"""
Зависимости для API (auth, db, etc.)
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import Optional
from app.core.database import get_db
from app.core.security import decode_token
from app.models.user import User
from app.services.subscription_service import SubscriptionService

security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db)
) -> Optional[User]:
    """Получить текущего пользователя из JWT token"""
    if not credentials:
        return None
    
    token = credentials.credentials
    payload = decode_token(token)
    
    if not payload or payload.get("type") != "access":
        return None
    
    user_id = payload.get("sub")
    if not user_id:
        return None
    
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user or user.deleted_at:
        return None
    
    return user


async def get_current_user_required(
    credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer()),
    db: Session = Depends(get_db)
) -> User:
    """Получить текущего пользователя (обязательно)"""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    token = credentials.credentials
    payload = decode_token(token)
    
    if not payload or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload"
        )
    
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user or user.deleted_at:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )
    if user.banned_at is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account suspended",
        )

    return user


async def get_current_admin_required(
    current_user: User = Depends(get_current_user_required)
) -> User:
    """Получить текущего пользователя, проверив что он админ"""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user


async def get_current_moderator_required(
    current_user: User = Depends(get_current_user_required)
) -> User:
    """Получить текущего пользователя, проверив что он модератор или админ"""
    if not (current_user.is_moderator or current_user.is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Moderator or admin access required"
        )
    return current_user


async def require_han_plus_subscriber(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
) -> User:
    """Совместимость: Plus = доступ к AI."""
    return await require_han_ai_subscriber(current_user, db)


async def require_han_ai_subscriber(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
) -> User:
    if not SubscriptionService(db).has_ai_access(current_user.id):
        from app.core.entitlements import HAN_AI_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_AI_REQUIRED_CODE,
                "message": "Требуется подписка H.A.N. AI или Pro",
            },
        )
    return current_user


async def require_han_creator_subscriber(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
) -> User:
    if not SubscriptionService(db).has_creator_access(current_user.id):
        from app.core.entitlements import HAN_CREATOR_REQUIRED_CODE

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": HAN_CREATOR_REQUIRED_CODE,
                "message": "Требуется подписка H.A.N. Creator или Pro",
            },
        )
    return current_user

