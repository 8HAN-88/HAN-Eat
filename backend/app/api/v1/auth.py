"""
API endpoints для аутентификации
"""
import logging
import re

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.config import settings
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
logger = logging.getLogger(__name__)


def _generate_unique_username(db: Session, email: str) -> str:
    """Логин из локальной части email, уникальный в БД (длина до 100)."""
    local = (email or "user").split("@", 1)[0].lower()
    slug = re.sub(r"[^a-z0-9_]", "_", local)
    slug = re.sub(r"_+", "_", slug).strip("_") or "user"
    if not slug[0].isalpha():
        slug = f"u_{slug}"
    slug = slug[:80]
    candidate = slug
    counter = 0
    while db.query(User).filter(User.username == candidate).first():
        counter += 1
        suffix = f"_{counter}"
        base_max = max(1, 100 - len(suffix))
        candidate = (slug[:base_max] + suffix)[:100]
    return candidate


async def _resolve_google_claims(id_token: str) -> dict:
    """
    Проверка id_token через Google tokeninfo.
    При SKIP_GOOGLE_ID_TOKEN_VERIFICATION=true только декодирование без проверки (только для отладки).
    """
    from jose import jwt

    if settings.SKIP_GOOGLE_ID_TOKEN_VERIFICATION:
        logger.warning(
            "SKIP_GOOGLE_ID_TOKEN_VERIFICATION=true: Google id_token не проверяется через tokeninfo"
        )
        return jwt.get_unverified_claims(id_token)

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": id_token},
            timeout=15.0,
        )

    if resp.status_code != 200:
        detail = "Invalid Google ID token"
        try:
            err_body = resp.json()
            if isinstance(err_body, dict) and err_body.get("error_description"):
                detail = str(err_body["error_description"])
        except Exception:
            pass
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=detail)

    claims = resp.json()
    allowed = [
        x.strip()
        for x in (settings.GOOGLE_OAUTH_CLIENT_IDS or "").split(",")
        if x.strip()
    ]
    aud = claims.get("aud") or claims.get("azp")
    if allowed and aud not in allowed:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            detail=(
                "Google token audience (aud) is not allowed for this server. "
                "Add your Web OAuth client ID to GOOGLE_OAUTH_CLIENT_IDS in backend/.env "
                f"(token aud={aud!r})."
            ),
        )
    if not allowed and not settings.SKIP_GOOGLE_ID_TOKEN_VERIFICATION:
        logger.warning(
            "GOOGLE_OAUTH_CLIENT_IDS is empty: id_token aud is not restricted (set Web client ID in production)"
        )

    ev = claims.get("email_verified")
    if str(ev).lower() in ("false", "0"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Google account email is not verified",
        )

    return claims


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
    
    # Создаем пользователя (5 стартовых AI scan, база для суточного начисления)
    from datetime import datetime

    from app.services.ai_scan_credits_service import FREE_START

    user = User(
        email=request.email,
        password_hash=get_password_hash(request.password),
        name=request.name,
        username=request.username,
        scan_credits=FREE_START,
        last_scan_credit_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    from app.services.ai_scan_credits_service import AiScanCreditsService

    user = AiScanCreditsService(db).refresh_user(user.id)

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

        if user.banned_at:
            logger.warning("Banned user login attempt: %s", request.email)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account suspended",
            )

        logger.info(f"Login successful for user: {user.id} ({request.email})")

        from app.services.ai_scan_credits_service import AiScanCreditsService

        user = AiScanCreditsService(db).refresh_user(user.id)

        # Убеждаемся, что is_private не None (для совместимости со старыми данными)
        if user.is_private is None:
            user.is_private = False
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
async def refresh_token(
    request: RefreshTokenRequest,
    db: Session = Depends(get_db),
):
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

    try:
        uid = int(user_id)
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user = db.query(User).filter(User.id == uid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )
    if user.deleted_at:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Account deleted",
        )
    if user.banned_at:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account suspended",
        )
    
    # Создаем новый access token
    new_access_token = create_access_token(data={"sub": user_id})
    new_refresh_token = create_refresh_token(data={"sub": user_id})
    
    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token
    }


@router.get("/google/readiness")
async def google_auth_readiness():
    """Проверка конфигурации Google Sign-In (без секретов)."""
    ids = [
        x.strip()
        for x in (settings.GOOGLE_OAUTH_CLIENT_IDS or "").split(",")
        if x.strip()
    ]
    return {
        "configured": bool(ids),
        "client_ids_count": len(ids),
        "skip_verification": settings.SKIP_GOOGLE_ID_TOKEN_VERIFICATION,
        "production_safe": bool(ids) and not settings.SKIP_GOOGLE_ID_TOKEN_VERIFICATION,
    }


@router.post("/google", response_model=AuthResponse)
async def google_auth(request: GoogleAuthRequest, db: Session = Depends(get_db)):
    """Вход/регистрация через Google (проверка id_token через Google tokeninfo, если не отключено)."""
    try:
        claims = await _resolve_google_claims(request.id_token)

        google_email = claims.get("email")
        google_name = claims.get("name", "Google User")

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
                username=_generate_unique_username(db, google_email),
            )
            db.add(user)
            db.commit()
            db.refresh(user)
        else:
            if user.deleted_at:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Account deleted",
                )
            if user.banned_at:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Account suspended",
                )

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

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Google authentication failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Google authentication failed: {str(e)}"
        )

