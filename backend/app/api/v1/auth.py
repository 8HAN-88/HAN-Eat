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
from app.api.dependencies import get_current_user, get_current_user_required
from app.schemas.auth import (
    RegisterRequest,
    LoginRequest,
    AuthResponse,
    RefreshTokenRequest,
    GoogleAuthRequest,
    YandexAuthRequest,
    MessageResponse,
    TokenBody,
    ForgotPasswordRequest,
    ResetPasswordRequest,
    ChangePasswordRequest,
    ChangeEmailRequest,
    ResendVerificationRequest,
)
from app.models.auth_token import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
)
from app.services.auth_email_service import (
    consume_token,
    is_email_verified,
    mark_email_verified,
    send_change_email_confirmation,
    send_password_reset_email,
    send_verify_email,
)
from app.services.yandex_oauth_service import (
    build_authorize_url,
    exchange_code_and_fetch_profile,
    yandex_oauth_configured,
)
from app.schemas.user import UserResponse
from app.models.user import User
from datetime import timedelta

router = APIRouter()
logger = logging.getLogger(__name__)

_FORGOT_PASSWORD_MSG = (
    "Если аккаунт с таким email существует, мы отправили письмо со ссылкой для сброса пароля."
)


def _user_response(user: User) -> UserResponse:
    data = UserResponse.model_validate(user)
    return data.model_copy(update={"email_verified": is_email_verified(user)})


def _auth_response(user: User, access_token: str, refresh_token: str, message: str | None = None) -> AuthResponse:
    return AuthResponse(
        token=access_token,
        refresh_token=refresh_token,
        user=_user_response(user),
        message=message,
    )


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

    verify_msg = None
    try:
        send_verify_email(db, user)
        db.commit()
        verify_msg = "На вашу почту отправлено письмо для подтверждения email."
    except Exception as mail_err:
        logger.warning("verify email send failed for %s: %s", user.email, mail_err)
        db.commit()

    try:
        return _auth_response(user, access_token, refresh_token, verify_msg)
    except Exception as validation_error:
        logger.error(f"UserResponse validation error during registration: {validation_error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User data validation failed: {str(validation_error)}",
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

        if settings.REQUIRE_EMAIL_VERIFICATION and not is_email_verified(user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "EMAIL_NOT_VERIFIED",
                    "message": "Подтвердите email. Проверьте почту или запросите письмо повторно.",
                },
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
            return _auth_response(user, access_token, refresh_token)
        except Exception as validation_error:
            logger.error(f"UserResponse validation error: {validation_error}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"User data validation failed: {str(validation_error)}",
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
            mark_email_verified(user)
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
        
        if not is_email_verified(user):
            mark_email_verified(user)
            db.commit()

        return _auth_response(user, access_token, refresh_token)

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Google authentication failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Google authentication failed: {str(e)}"
        )


@router.get("/yandex/readiness")
async def yandex_auth_readiness():
    """Проверка конфигурации Яндекс ID (без секретов)."""
    return {
        "configured": yandex_oauth_configured(),
        "authorize_url_hint": "https://oauth.yandex.ru",
    }


@router.get("/yandex/authorize-url")
async def yandex_authorize_url(redirect_uri: str):
    """URL для открытия в браузере / WebAuth (client_id публичный)."""
    if not yandex_oauth_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Yandex OAuth is not configured",
        )
    return {"authorize_url": build_authorize_url(redirect_uri=redirect_uri)}


@router.post("/yandex", response_model=AuthResponse)
async def yandex_auth(request: YandexAuthRequest, db: Session = Depends(get_db)):
    """Вход/регистрация через Яндекс ID (authorization code)."""
    import secrets

    try:
        profile = await exchange_code_and_fetch_profile(
            request.code.strip(),
            request.redirect_uri.strip(),
        )
        yandex_email = profile["email"]
        yandex_name = profile["name"]

        user = db.query(User).filter(User.email == yandex_email).first()

        if not user:
            random_password = secrets.token_urlsafe(32)
            user = User(
                email=yandex_email,
                password_hash=get_password_hash(random_password),
                name=yandex_name,
                username=_generate_unique_username(db, yandex_email),
            )
            mark_email_verified(user)
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
            if yandex_name and (not user.name or user.name.strip() == ""):
                user.name = yandex_name
                db.commit()

        if user.is_private is None:
            user.is_private = False
            db.commit()

        access_token = create_access_token(data={"sub": str(user.id)})
        refresh_token = create_refresh_token(data={"sub": str(user.id)})

        if not is_email_verified(user):
            mark_email_verified(user)
            db.commit()

        return _auth_response(user, access_token, refresh_token)

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Yandex authentication failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Yandex authentication failed: {str(e)}",
        )


@router.post("/verify-email", response_model=MessageResponse)
async def verify_email(body: TokenBody, db: Session = Depends(get_db)):
    row, err = consume_token(db, body.token.strip(), PURPOSE_VERIFY_EMAIL)
    if err:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=err)
    user = db.query(User).filter(User.id == row.user_id).first()
    if not user or user.deleted_at:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="User not found")
    mark_email_verified(user)
    db.commit()
    return MessageResponse(message="Email подтверждён. Теперь можно войти в приложение.")


@router.post("/forgot-password", response_model=MessageResponse)
async def forgot_password(body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    from sqlalchemy import func

    email_norm = str(body.email).strip().lower()
    user = db.query(User).filter(func.lower(User.email) == email_norm).first()
    if user and not user.deleted_at and not user.banned_at:
        try:
            sent = send_password_reset_email(db, user)
            if sent:
                db.commit()
            else:
                db.rollback()
                logger.error(
                    "forgot-password: SMTP не отправил письмо user_id=%s email=%s",
                    user.id,
                    user.email,
                )
        except Exception as e:
            logger.warning("forgot-password email failed: %s", e)
            db.rollback()
    return MessageResponse(message=_FORGOT_PASSWORD_MSG)


@router.post("/reset-password", response_model=MessageResponse)
async def reset_password(body: ResetPasswordRequest, db: Session = Depends(get_db)):
    row, err = consume_token(db, body.token.strip(), PURPOSE_RESET_PASSWORD)
    if err:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=err)
    user = db.query(User).filter(User.id == row.user_id).first()
    if not user or user.deleted_at:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="User not found")
    user.password_hash = get_password_hash(body.new_password)
    db.commit()
    return MessageResponse(message="Пароль обновлён. Войдите с новым паролем.")


@router.post("/change-password", response_model=MessageResponse)
async def change_password(
    body: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user_required),
):
    if not verify_password(body.current_password, current_user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Неверный текущий пароль")
    if body.current_password == body.new_password:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Новый пароль должен отличаться от текущего",
        )
    current_user.password_hash = get_password_hash(body.new_password)
    db.commit()
    return MessageResponse(message="Пароль изменён")


@router.post("/change-email", response_model=MessageResponse)
async def change_email_request(
    body: ChangeEmailRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user_required),
):
    if not verify_password(body.password, current_user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Неверный пароль")
    new_email = body.new_email.strip().lower()
    if new_email == current_user.email.lower():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Это уже ваш текущий email")
    existing = db.query(User).filter(User.email == new_email).first()
    if existing and existing.id != current_user.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Email уже занят")
    try:
        send_change_email_confirmation(db, current_user, new_email)
        db.commit()
    except Exception as e:
        logger.warning("change-email email failed: %s", e)
        db.rollback()
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Не удалось отправить письмо. Попробуйте позже.",
        )
    return MessageResponse(
        message=f"Письмо с подтверждением отправлено на {new_email}",
    )


@router.post("/confirm-email-change", response_model=MessageResponse)
async def confirm_email_change(body: TokenBody, db: Session = Depends(get_db)):
    import json

    row, err = consume_token(db, body.token.strip(), PURPOSE_CHANGE_EMAIL)
    if err:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=err)
    if not row.extra_data:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid token data")
    try:
        payload = json.loads(row.extra_data)
        new_email = (payload.get("new_email") or "").strip().lower()
    except json.JSONDecodeError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid token data")
    if not new_email:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid token data")
    user = db.query(User).filter(User.id == row.user_id).first()
    if not user or user.deleted_at:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="User not found")
    existing = db.query(User).filter(User.email == new_email, User.id != user.id).first()
    if existing:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Email уже занят")
    user.email = new_email
    mark_email_verified(user)
    db.commit()
    return MessageResponse(message="Email обновлён")


@router.post("/resend-verification", response_model=MessageResponse)
async def resend_verification(
    body: ResendVerificationRequest,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_current_user),
):
    email = (body.email or "").strip().lower() if body.email else None
    if not email and current_user:
        email = current_user.email.lower()
    if not email:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Укажите email")

    user = db.query(User).filter(User.email == email).first()
    if user and not user.deleted_at and not is_email_verified(user):
        try:
            send_verify_email(db, user)
            db.commit()
        except Exception as e:
            logger.warning("resend verification failed: %s", e)
            db.rollback()

    return MessageResponse(
        message="Если аккаунт существует и email не подтверждён, письмо отправлено.",
    )


