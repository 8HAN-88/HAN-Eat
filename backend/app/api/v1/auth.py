"""
API endpoints для аутентификации
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.schemas.auth import RegisterRequest, LoginRequest, AuthResponse, RefreshTokenRequest, GoogleAuthRequest
from app.schemas.user import UserResponse
from app.models.user import User
from datetime import timedelta

router = APIRouter()


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(request: RegisterRequest, db: Session = Depends(get_db)):
    """Регистрация нового пользователя"""
    # Проверяем, существует ли пользователь
    existing_user = db.query(User).filter(User.email == request.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )
    
    # Проверяем username, если указан
    if request.username:
        existing_username = db.query(User).filter(User.username == request.username).first()
        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already taken"
            )
    
    # Создаем пользователя
    user = User(
        email=request.email,
        password_hash=get_password_hash(request.password),
        name=request.name,
        username=request.username,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    
    # Убеждаемся, что is_private не None
    if user.is_private is None:
        user.is_private = False
        db.commit()
    
    # Создаем токены
    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})
    
    try:
        user_response = UserResponse.model_validate(user)
    except Exception as validation_error:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"UserResponse validation error during registration: {validation_error}")
        logger.error(f"User data: id={user.id}, email={user.email}, is_private={user.is_private}, created_at={user.created_at}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User data validation failed: {str(validation_error)}"
        )
    
    return AuthResponse(
        token=access_token,
        refresh_token=refresh_token,
        user=user_response
    )


@router.post("/login", response_model=AuthResponse)
async def login(request: LoginRequest, db: Session = Depends(get_db)):
    """Вход пользователя"""
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        logger.info(f"Login attempt for email: {request.email}")
        user = db.query(User).filter(User.email == request.email).first()
        
        if not user:
            logger.warning(f"User not found: {request.email}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password"
            )
        
        if not verify_password(request.password, user.password_hash):
            logger.warning(f"Invalid password for user: {request.email}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password"
            )
        
        if user.deleted_at:
            logger.warning(f"Attempt to login to deleted account: {request.email}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account deleted"
            )
        
        logger.info(f"Login successful for user: {user.id} ({request.email})")
        
        # Убеждаемся, что is_private не None (для совместимости со старыми данными)
        if user.is_private is None:
            user.is_private = False
            # Сохраняем в базу данных
            db.commit()
        
        # Создаем токены
        access_token = create_access_token(data={"sub": str(user.id)})
        refresh_token = create_refresh_token(data={"sub": str(user.id)})
        
        try:
            user_response = UserResponse.model_validate(user)
        except Exception as validation_error:
            logger.error(f"UserResponse validation error: {validation_error}")
            logger.error(f"User data: id={user.id}, email={user.email}, is_private={user.is_private}, created_at={user.created_at}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"User data validation failed: {str(validation_error)}"
            )
        
        return AuthResponse(
            token=access_token,
            refresh_token=refresh_token,
            user=user_response
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error during login: {e}", exc_info=True)
        import traceback
        error_details = traceback.format_exc()
        logger.error(f"Full traceback: {error_details}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error during login: {str(e)}"
        )


@router.post("/refresh", response_model=dict)
async def refresh_token(request: RefreshTokenRequest):
    """Обновление access token"""
    payload = decode_token(request.refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )
    
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload"
        )
    
    # Создаем новый access token
    new_access_token = create_access_token(data={"sub": user_id})
    new_refresh_token = create_refresh_token(data={"sub": user_id})
    
    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token
    }


@router.post("/google", response_model=AuthResponse)
async def google_auth(request: GoogleAuthRequest, db: Session = Depends(get_db)):
    """Вход/регистрация через Google"""
    from jose import jwt
    
    try:
        # Верифицируем Google ID token
        # Для production нужно использовать Google API для верификации
        # Здесь упрощенная версия - декодируем без верификации (только для разработки)
        # В production используйте: https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=...
        
        # Декодируем токен (без верификации для упрощения, в production нужна верификация)
        unverified = jwt.get_unverified_claims(request.id_token)
        
        google_email = unverified.get("email")
        google_name = unverified.get("name", "Google User")
        google_sub = unverified.get("sub")  # Google user ID
        
        if not google_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid Google token: missing email"
            )
        
        # Ищем существующего пользователя по email
        user = db.query(User).filter(User.email == google_email).first()
        
        if not user:
            # Создаем нового пользователя
            # Генерируем случайный пароль (пользователь не будет его использовать)
            import secrets
            random_password = secrets.token_urlsafe(32)
            
            user = User(
                email=google_email,
                password_hash=get_password_hash(random_password),
                name=google_name,
                username=None,  # Можно добавить генерацию username
            )
            db.add(user)
            db.commit()
            db.refresh(user)
        
        # Убеждаемся, что is_private не None
        if user.is_private is None:
            user.is_private = False
            db.commit()
        
        # Создаем токены
        access_token = create_access_token(data={"sub": str(user.id)})
        refresh_token = create_refresh_token(data={"sub": str(user.id)})
        
        try:
            user_response = UserResponse.model_validate(user)
        except Exception as validation_error:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"UserResponse validation error during Google auth: {validation_error}")
            logger.error(f"User data: id={user.id}, email={user.email}, is_private={user.is_private}, created_at={user.created_at}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"User data validation failed: {str(validation_error)}"
            )
        
        return AuthResponse(
            token=access_token,
            refresh_token=refresh_token,
            user=user_response
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Google authentication failed: {str(e)}"
        )

