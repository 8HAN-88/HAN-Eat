"""
Pydantic схемы для аутентификации
"""
from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    name: str = Field(..., min_length=1, max_length=255)
    username: str | None = Field(None, max_length=100)
    accept_legal: bool = Field(
        ...,
        description="Согласие с политикой конфиденциальности и пользовательским соглашением",
    )


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    token: str
    refresh_token: str
    user: "UserResponse"
    message: str | None = None
    session_id: int | None = None


class MessageResponse(BaseModel):
    message: str


class TokenBody(BaseModel):
    token: str = Field(..., min_length=16)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str = Field(..., min_length=16)
    new_password: str = Field(..., min_length=8)


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=8)


class ChangeEmailRequest(BaseModel):
    new_email: EmailStr
    password: str


class ResendVerificationRequest(BaseModel):
    email: EmailStr | None = None


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class AuthSessionResponse(BaseModel):
    id: int
    device_name: str | None = None
    device_platform: str | None = None
    ip_address: str | None = None
    created_at: str
    last_seen_at: str
    is_current: bool = False


class AuthSessionListResponse(BaseModel):
    items: list[AuthSessionResponse]


class GoogleAuthRequest(BaseModel):
    id_token: str
    accept_legal: bool = False


class YandexAuthRequest(BaseModel):
    code: str
    redirect_uri: str
    accept_legal: bool = False


class LegalAcceptRequest(BaseModel):
    accept_legal: bool = Field(
        ...,
        description="Подтверждение актуальной версии privacy + terms",
    )


from app.schemas.user import UserResponse

AuthResponse.model_rebuild()

