"""
Pydantic схемы для аутентификации
"""
from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    name: str = Field(..., min_length=1, max_length=255)
    username: str | None = Field(None, max_length=100)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    token: str
    refresh_token: str
    user: "UserResponse"
    message: str | None = None


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


class GoogleAuthRequest(BaseModel):
    id_token: str


class YandexAuthRequest(BaseModel):
    code: str
    redirect_uri: str


from app.schemas.user import UserResponse

AuthResponse.model_rebuild()

