"""
API endpoints для аутентификации
"""
import logging
import re

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
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
    AuthSessionListResponse,
    AuthSessionResponse,
    TotpStatusResponse,
    TotpSetupResponse,
    TotpCodeRequest,
    TotpDisableRequest,
    TotpVerifyLoginRequest,
)
from app.services.totp_service import (
    ISSUER as TOTP_ISSUER,
    create_pending_token,
    decode_pending_token,
    generate_secret,
    is_2fa_enabled,
    provisioning_uri,
    verify_code as verify_totp_code,
)
from app.models.auth_token import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
)
from app.services.auth_link_redirect import render_open_link_page
from app.services.auth_email_service import (
    consume_token,
    is_email_verified,
    mark_email_verified,
    send_change_email_confirmation,
    send_password_reset_email,
    send_verify_email,
)
from app.services.email_delivery_service import EmailDeliveryError
from app.services.yandex_oauth_service import (
    build_authorize_url,
    exchange_code_and_fetch_profile,
    yandex_oauth_configured,
)
from app.schemas.user import UserResponse
from app.models.user import User
from datetime import datetime, timedelta

router = APIRouter()
logger = logging.getLogger(__name__)

_FORGOT_PASSWORD_MSG = (
    "Если аккаунт с таким email существует, мы отправили письмо со ссылкой для сброса пароля."
)

_AUTH_OPEN_PURPOSES = frozenset(
    {"verify-email", "reset-password", "confirm-email-change"}
)


def _user_response(user: User, db: Session | None = None) -> UserResponse:
    from app.services.legal_consent_service import user_legal_fields

    data = UserResponse.model_validate(user, context={"include_phone": True})
    legal = user_legal_fields(user)
    updates = {
        "email_verified": is_email_verified(user),
        **legal,
    }
    if db is not None:
        from app.services.emoji_pack_service import EmojiPackService

        updates["emoji_status"] = EmojiPackService(db).visible_emoji_status(user)
    return data.model_copy(update=updates)



def _client_meta(request: Request | None) -> dict[str, str | None]:
    if request is None:
        return {
            "device_name": None,
            "device_platform": None,
            "user_agent": None,
            "ip_address": None,
        }
    headers = request.headers
    ua = (headers.get("user-agent") or "").strip() or None
    return {
        "device_name": (headers.get("x-client-device") or "").strip() or None,
        "device_platform": (headers.get("x-client-platform") or "").strip() or None,
        "user_agent": ua[:512] if ua else None,
        "ip_address": request.client.host if request.client else None,
    }


def _issue_auth_tokens(
    db: Session,
    user: User,
    request: Request | None = None,
) -> tuple[str, str, int]:
    from app.services.auth_session_service import create_session

    meta = _client_meta(request)
    access, refresh, session = create_session(
        db,
        user=user,
        device_name=meta["device_name"],
        device_platform=meta["device_platform"],
        user_agent=meta["user_agent"],
        ip_address=meta["ip_address"],
    )
    db.commit()
    return access, refresh, session.id


def _session_response(row, *, current_session_id: int | None) -> AuthSessionResponse:
    return AuthSessionResponse(
        id=row.id,
        device_name=row.device_name,
        device_platform=row.device_platform,
        ip_address=row.ip_address,
        created_at=row.created_at.isoformat() if row.created_at else "",
        last_seen_at=row.last_seen_at.isoformat() if row.last_seen_at else "",
        is_current=bool(current_session_id and row.id == current_session_id),
    )


def _auth_response(
    user: User,
    access_token: str,
    refresh_token: str,
    message: str | None = None,
    session_id: int | None = None,
    db: Session | None = None,
) -> AuthResponse:
    return AuthResponse(
        token=access_token,
        refresh_token=refresh_token,
        user=_user_response(user, db),
        message=message,
        session_id=session_id,
    )


def _raise_two_factor_required(user: User) -> None:
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={
            "code": "TWO_FACTOR_REQUIRED",
            "message": "Введите код из приложения-аутентификатора.",
            "pending_token": create_pending_token(user.id),
        },
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
async def register(
    request: RegisterRequest,
    background_tasks: BackgroundTasks,
    http_request: Request,
    db: Session = Depends(get_db),
):
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

    if not request.accept_legal:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "LEGAL_CONSENT_REQUIRED",
                "message": (
                    "Необходимо принять политику конфиденциальности "
                    "и пользовательское соглашение"
                ),
            },
        )

    from app.core.entitlements import feature_required_detail
    from app.services.emoji_pack_service import parse_custom_emoji_ids

    # New accounts have no flex — custom-emoji tokens are always forbidden.
    if parse_custom_emoji_ids(request.name) or parse_custom_emoji_ids(
        request.username
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=feature_required_detail(
                "custom_emoji",
                "Кастомные эмодзи в тексте доступны с уровня 69",
            ),
        )
    
    # Создаем пользователя (scan_credits поле legacy; kitchen AI-scan retired)
    from datetime import datetime

    user = User(
        email=request.email,
        password_hash=get_password_hash(request.password),
        name=request.name,
        username=request.username or _generate_unique_username(db, request.email),
        scan_credits=0,
        last_scan_credit_at=None,
    )
    from app.services.legal_consent_service import record_consent

    record_consent(user, db)
    db.add(user)
    db.commit()
    db.refresh(user)

    # Убеждаемся, что is_private не None
    if user.is_private is None:
        user.is_private = False
        db.commit()

    access_token, refresh_token, session_id = _issue_auth_tokens(db, user, http_request)

    verify_msg = None
    try:
        send_verify_email(db, user)
        db.commit()
        verify_msg = (
            "На вашу почту отправлено письмо для подтверждения email. "
            "Проверьте также папку «Спам»."
        )
    except EmailDeliveryError as mail_err:
        logger.error("verify email send failed for %s: %s", user.email, mail_err)
        db.commit()
        verify_msg = (
            "Аккаунт создан, но письмо не удалось отправить. "
            "Нажмите «Отправить письмо ещё раз» или обратитесь в поддержку."
        )
    except Exception as mail_err:
        logger.warning("verify email send failed for %s: %s", user.email, mail_err)
        db.commit()
        verify_msg = (
            "Аккаунт создан, но письмо не удалось отправить. "
            "Попробуйте «Отправить письмо ещё раз»."
        )

    try:
        return _auth_response(
            user, access_token, refresh_token, verify_msg, session_id, db=db
        )
    except Exception as validation_error:
        logger.error(f"UserResponse validation error during registration: {validation_error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User data validation failed: {str(validation_error)}",
        )


@router.post("/login", response_model=AuthResponse)
async def login(
    request: LoginRequest,
    background_tasks: BackgroundTasks,
    http_request: Request,
    db: Session = Depends(get_db),
):
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

        if is_2fa_enabled(user):
            logger.info("2FA challenge for user: %s", user.id)
            _raise_two_factor_required(user)

        logger.info(f"Login successful for user: {user.id} ({request.email})")

        # Убеждаемся, что is_private не None (для совместимости со старыми данными)
        if user.is_private is None:
            user.is_private = False
            db.commit()

        access_token, refresh_token, session_id = _issue_auth_tokens(db, user, http_request)

        try:
            return _auth_response(
                user, access_token, refresh_token, session_id=session_id, db=db
            )
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
    http_request: Request,
    db: Session = Depends(get_db),
):
    """Обновление access token"""
    from app.services.auth_session_service import (
        get_active_session,
        rotate_session_tokens,
        create_session,
    )

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

    sid = payload.get("sid")
    jti = payload.get("jti")
    if sid is not None:
        try:
            sid_int = int(sid)
        except (TypeError, ValueError):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token",
            )
        session = get_active_session(db, session_id=sid_int, jti=jti)
        if session is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Session revoked",
            )
        new_access_token, new_refresh_token = rotate_session_tokens(
            db, session=session, user=user
        )
        session_id = session.id
        db.commit()
    else:
        # Legacy refresh tokens without session binding: mint a tracked session.
        meta = _client_meta(http_request)
        new_access_token, new_refresh_token, session = create_session(
            db,
            user=user,
            device_name=meta["device_name"],
            device_platform=meta["device_platform"],
            user_agent=meta["user_agent"],
            ip_address=meta["ip_address"],
        )
        session_id = session.id
        db.commit()
    
    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token,
        "session_id": session_id,
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
async def google_auth(request: GoogleAuthRequest, http_request: Request, db: Session = Depends(get_db)):
    """Вход/регистрация через Google (проверка id_token через Google tokeninfo, если не отключено)."""
    try:
        claims = await _resolve_google_claims(request.id_token)

        from app.services.emoji_pack_service import strip_custom_emoji_tokens

        google_email = claims.get("email")
        google_name = strip_custom_emoji_tokens(claims.get("name") or "") or "Google User"

        if not google_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid Google token: missing email"
            )
        
        # Ищем существующего пользователя по email
        user = db.query(User).filter(User.email == google_email).first()
        
        is_new_user = user is None
        if is_new_user:
            if not request.accept_legal:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "code": "LEGAL_CONSENT_REQUIRED",
                        "message": (
                            "Для регистрации через Google примите политику "
                            "конфиденциальности и пользовательское соглашение"
                        ),
                    },
                )
            import secrets

            random_password = secrets.token_urlsafe(32)
            user = User(
                email=google_email,
                password_hash=get_password_hash(random_password),
                name=google_name,
                username=_generate_unique_username(db, google_email),
            )
            mark_email_verified(user)
            from app.services.legal_consent_service import record_consent

            record_consent(user, db)
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
            if is_2fa_enabled(user):
                _raise_two_factor_required(user)

        if user.is_private is None:
            user.is_private = False
            db.commit()

        access_token, refresh_token, session_id = _issue_auth_tokens(db, user, http_request)

        if not is_email_verified(user):
            mark_email_verified(user)
            db.commit()

        return _auth_response(
            user, access_token, refresh_token, session_id=session_id, db=db
        )

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
async def yandex_auth(request: YandexAuthRequest, http_request: Request, db: Session = Depends(get_db)):
    """Вход/регистрация через Яндекс ID (authorization code)."""
    import secrets

    try:
        profile = await exchange_code_and_fetch_profile(
            request.code.strip(),
            request.redirect_uri.strip(),
        )
        from app.services.emoji_pack_service import strip_custom_emoji_tokens

        yandex_email = profile["email"]
        yandex_name = strip_custom_emoji_tokens(profile.get("name") or "") or "Yandex User"

        user = db.query(User).filter(User.email == yandex_email).first()

        if not user:
            if not request.accept_legal:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "code": "LEGAL_CONSENT_REQUIRED",
                        "message": (
                            "Для регистрации через Яндекс примите политику "
                            "конфиденциальности и пользовательское соглашение"
                        ),
                    },
                )
            random_password = secrets.token_urlsafe(32)
            user = User(
                email=yandex_email,
                password_hash=get_password_hash(random_password),
                name=yandex_name,
                username=_generate_unique_username(db, yandex_email),
            )
            mark_email_verified(user)
            from app.services.legal_consent_service import record_consent

            record_consent(user, db)
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
            if is_2fa_enabled(user):
                _raise_two_factor_required(user)

        if user.is_private is None:
            user.is_private = False
            db.commit()

        access_token, refresh_token, session_id = _issue_auth_tokens(db, user, http_request)

        if not is_email_verified(user):
            mark_email_verified(user)
            db.commit()

        return _auth_response(
            user, access_token, refresh_token, session_id=session_id, db=db
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Yandex authentication failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Yandex authentication failed: {str(e)}",
        )


@router.get("/open/{purpose}", response_class=HTMLResponse)
async def open_auth_email_link(purpose: str, token: str = ""):
    """Страница из письма: редирект в приложение (haneat://) + код для ручного ввода."""
    if purpose not in _AUTH_OPEN_PURPOSES:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Not found")
    token = token.strip()
    if len(token) < 16:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid token")
    return HTMLResponse(render_open_link_page(purpose, token))


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
            return MessageResponse(
                message=(
                    "Письмо отправлено. Проверьте входящие и папку «Спам» "
                    "(для mail.ru письма часто попадают в «Нежелательная почта»)."
                ),
            )
        except EmailDeliveryError as e:
            logger.error("resend verification failed for %s: %s", email, e)
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=(
                    "Не удалось отправить письмо. Попробуйте позже или "
                    "обратитесь в поддержку."
                ),
            )
        except Exception as e:
            logger.warning("resend verification failed: %s", e)
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Не удалось отправить письмо. Попробуйте позже.",
            )

    return MessageResponse(
        message="Если аккаунт существует и email не подтверждён, письмо отправлено.",
    )


def _current_session_id_from_auth_header(request: Request) -> int | None:
    # Clients send the current auth session id from login/refresh response.
    raw = (request.headers.get("x-auth-session-id") or "").strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


@router.get("/sessions", response_model=AuthSessionListResponse)
async def list_auth_sessions(
    http_request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.auth_session_service import list_sessions

    current_id = _current_session_id_from_auth_header(http_request)
    items = list_sessions(db, user_id=current_user.id)
    return AuthSessionListResponse(
        items=[
            _session_response(row, current_session_id=current_id) for row in items
        ]
    )


@router.delete("/sessions/{session_id}", response_model=MessageResponse)
async def revoke_auth_session(
    session_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.auth_session_service import revoke_session

    row = revoke_session(db, user_id=current_user.id, session_id=session_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Session not found")
    db.commit()
    return MessageResponse(message="Session revoked")


@router.post("/sessions/revoke-others", response_model=MessageResponse)
async def revoke_other_auth_sessions(
    http_request: Request,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.auth_session_service import revoke_other_sessions

    current_id = _current_session_id_from_auth_header(http_request)
    if current_id is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Current session id required (X-Auth-Session-Id)",
        )
    count = revoke_other_sessions(
        db, user_id=current_user.id, keep_session_id=current_id
    )
    db.commit()
    return MessageResponse(message=f"Revoked {count} sessions")


@router.post("/sessions/revoke-all", response_model=MessageResponse)
async def revoke_all_auth_sessions(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    from app.services.auth_session_service import revoke_all_sessions

    count = revoke_all_sessions(db, user_id=current_user.id)
    db.commit()
    return MessageResponse(message=f"Revoked {count} sessions")


@router.get("/2fa/status", response_model=TotpStatusResponse)
async def totp_status(
    current_user: User = Depends(get_current_user_required),
):
    return TotpStatusResponse(enabled=is_2fa_enabled(current_user))


@router.post("/2fa/setup", response_model=TotpSetupResponse)
async def totp_setup(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    """Generate a new TOTP secret (does not enable until /2fa/enable)."""
    if is_2fa_enabled(current_user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is already enabled",
        )
    secret = generate_secret()
    account = current_user.email or current_user.username or str(current_user.id)
    uri = provisioning_uri(secret, account)
    current_user.totp_secret = secret
    current_user.totp_enabled = False
    current_user.totp_enabled_at = None
    db.commit()
    return TotpSetupResponse(secret=secret, otpauth_uri=uri, issuer=TOTP_ISSUER)


@router.post("/2fa/enable", response_model=MessageResponse)
async def totp_enable(
    body: TotpCodeRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if is_2fa_enabled(current_user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is already enabled",
        )
    secret = getattr(current_user, "totp_secret", None)
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Call /auth/2fa/setup first",
        )
    if not verify_totp_code(secret, body.code):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid authenticator code",
        )

    current_user.totp_enabled = True
    current_user.totp_enabled_at = datetime.utcnow()
    db.commit()
    return MessageResponse(message="Two-factor authentication enabled")


@router.post("/2fa/disable", response_model=MessageResponse)
async def totp_disable(
    body: TotpDisableRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if not is_2fa_enabled(current_user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is not enabled",
        )
    if not verify_password(body.password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect password",
        )
    if not verify_totp_code(current_user.totp_secret or "", body.code):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid authenticator code",
        )
    current_user.totp_secret = None
    current_user.totp_enabled = False
    current_user.totp_enabled_at = None
    db.commit()
    return MessageResponse(message="Two-factor authentication disabled")


@router.post("/2fa/verify-login", response_model=AuthResponse)
async def totp_verify_login(
    body: TotpVerifyLoginRequest,
    http_request: Request,
    db: Session = Depends(get_db),
):
    """Complete login after password/OAuth when 2FA is required."""
    user_id = decode_pending_token(body.pending_token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired 2FA pending token",
        )
    user = db.query(User).filter(User.id == user_id).first()
    if not user or user.deleted_at or user.banned_at:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired 2FA pending token",
        )
    if not is_2fa_enabled(user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is not enabled",
        )
    if not verify_totp_code(user.totp_secret or "", body.code):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authenticator code",
        )
    if user.is_private is None:
        user.is_private = False
        db.commit()
    access_token, refresh_token, session_id = _issue_auth_tokens(db, user, http_request)
    return _auth_response(
        user, access_token, refresh_token, session_id=session_id, db=db
    )
