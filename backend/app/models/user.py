"""
Модель пользователя
"""
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text, Float
from sqlalchemy.sql import func
from app.core.database import Base


class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    email_verified_at = Column(DateTime, nullable=True)
    password_hash = Column(String(255), nullable=False)
    name = Column(String(255), nullable=False)
    username = Column(String(100), unique=True, index=True, nullable=True)
    avatar_url = Column(Text, nullable=True)
    bio = Column(Text, nullable=True)
    is_private = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    subscription_type = Column(String(20), default="free")  # free | ai | creator | pro
    subscription_status = Column(String(20), default="active", nullable=False)  # active | expired | canceled | trial
    subscription_expires_at = Column(DateTime, nullable=True)
    subscription_platform = Column(String(20), nullable=True)  # ios | android | yookassa | stripe
    subscription_auto_renew = Column(Boolean, default=False, nullable=False)
    # Сохранённый способ оплаты ЮKassa (СБП) для безакцептных продлений (legacy)
    yookassa_payment_method_id = Column(String(64), nullable=True)
    # RebillId Т-Банк для рекуррентных списаний (СБП / карта)
    tbank_rebill_id = Column(String(64), nullable=True)
    legal_consent_version = Column(String(32), nullable=True)
    legal_consent_at = Column(DateTime, nullable=True)
    # Legacy kitchen AI-scan credits (unused in messenger product)
    scan_credits = Column(Integer, default=5, nullable=False)
    last_scan_credit_at = Column(DateTime, nullable=True)
    # Legacy kitchen meal-plan cooldown fields
    meal_plan_last_generated_at = Column(DateTime, nullable=True)
    meal_plan_cooldown_ends_at = Column(DateTime, nullable=True)
    is_admin = Column(Boolean, default=False, nullable=False)
    is_moderator = Column(Boolean, default=False, nullable=False)
    trust_score = Column(Float, default=0.5, nullable=False)
    account_warnings = Column(Integer, default=0, nullable=False)
    shadow_moderation = Column(Boolean, default=False, nullable=False)
    banned_at = Column(DateTime, nullable=True)

    # === Боты (BotFather) ===
    is_bot = Column(Boolean, default=False, nullable=False)
    bot_token = Column(String(64), unique=True, nullable=True, index=True)
    bot_username = Column(String(32), unique=True, nullable=True, index=True)
    bot_description = Column(Text, nullable=True)
    bot_short_description = Column(String(120), nullable=True)
    bot_avatar_url = Column(Text, nullable=True)
    bot_webhook_url = Column(String(500), nullable=True)
    bot_webhook_secret = Column(String(128), nullable=True)
    bot_webhook_enabled = Column(Boolean, default=False, nullable=False)
    bot_webhook_last_error = Column(Text, nullable=True)
    bot_webhook_last_ok_at = Column(DateTime, nullable=True)
    created_by_user_id = Column(Integer, nullable=True)  # кто создал бота (для is_bot=True)
    fcm_token = Column(String(500), nullable=True)  # Firebase Cloud Messaging token (для Android и iOS)
    # iOS PushKit VoIP token for CallKit when the app is killed.
    voip_token = Column(String(500), nullable=True)
    device_platform = Column(String(20), nullable=True)  # android | ios | web
    country_code = Column(String(2), nullable=True)  # ISO 3166-1 alpha-2 код страны (RU, US, etc.)
    last_seen_at = Column(DateTime, nullable=True)
    # When False, last_seen_at is hidden from other users in chat payloads.
    show_last_seen = Column(Boolean, default=True, nullable=False)
    # Telegram-like tiers: everybody | contacts | nobody (show_last_seen kept in sync).
    last_seen_privacy = Column(String(20), default="everybody", nullable=False)
    # When False, read receipts (blue ticks / message.read) are hidden mutually.
    show_read_receipts = Column(Boolean, default=True, nullable=False)
    # Telegram-like: charge this many Stars per incoming DM (0 = free).
    paid_message_stars = Column(Integer, default=0, nullable=False)
    # TON wallet for creator Stars cash-out (Fragment-like).
    ton_address = Column(String(128), nullable=True)
    phone_hash = Column(String(64), nullable=True, unique=True, index=True)
    phone_e164 = Column(String(20), nullable=True)
    phone_linked_at = Column(DateTime, nullable=True)
    # TOTP 2FA (Google Authenticator / Authy)
    totp_secret = Column(String(64), nullable=True)
    totp_enabled = Column(Boolean, default=False, nullable=False)
    totp_enabled_at = Column(DateTime, nullable=True)
    # Telegram Premium: emoji next to name + account name color.
    emoji_status = Column(String(16), nullable=True)
    profile_color = Column(String(16), nullable=True)
    # Telegram Premium: who may send voice / video notes to this user.
    voice_privacy = Column(String(20), default="everybody", nullable=False)
    # Auto-archive + mute new DMs from non-contacts.
    archive_non_contacts = Column(Boolean, default=False, nullable=False)
    # Chat folder opened on app launch.
    default_folder_id = Column(Integer, nullable=True)
    # Telegram Premium: view stories without appearing in viewers.
    story_stealth = Column(Boolean, default=False, nullable=False)
    # Telegram Premium: who may call this user.
    call_privacy = Column(String(20), default="everybody", nullable=False)
    group_add_privacy = Column(String(20), default="everybody", nullable=False)
    dm_privacy = Column(String(20), default="everybody", nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    deleted_at = Column(DateTime, nullable=True)

