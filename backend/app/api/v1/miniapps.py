"""API платформы мини-приложений HanWe."""
from __future__ import annotations

import ipaddress
import hashlib
import hmac
import json
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required as get_current_user
from app.api.dependencies import get_current_user as get_optional_user
from app.api.dependencies import get_current_moderator_required
from app.core.config import settings
from app.core.database import get_db
from app.core.redis_client import REDIS_IS_STUB, get_redis
from app.models.miniapp import BotMiniApp, MiniAppInstall, MiniAppLaunch
from app.models.user import User

router = APIRouter(prefix="/miniapps", tags=["Mini Apps"])

# Telegram-like catalog categories (no kitchen/recipes product surface).
MINIAPP_CATEGORIES = (
    "tools",
    "games",
    "entertainment",
    "shopping",
    "other",
)


def _is_private_or_local_host(host: str) -> bool:
    normalized = (host or "").strip().lower()
    if not normalized:
        return True
    if normalized in {"localhost", "127.0.0.1", "::1"}:
        return True
    if normalized.endswith(".local") or normalized.endswith(".internal"):
        return True
    try:
        ip = ipaddress.ip_address(normalized)
        return any(
            [
                ip.is_private,
                ip.is_loopback,
                ip.is_link_local,
                ip.is_multicast,
                ip.is_reserved,
                ip.is_unspecified,
            ]
        )
    except ValueError:
        return False


def _host_allowed(host: str, allowed_hosts: set[str]) -> bool:
    if host in allowed_hosts:
        return True
    return any(host.endswith(f".{base}") for base in allowed_hosts)


def _url_risk_summary(url: str) -> dict:
    parsed = urlparse((url or "").strip())
    host = (parsed.hostname or "").lower()
    scheme = (parsed.scheme or "").lower()
    reasons: List[str] = []
    if scheme != "https":
        reasons.append("non_https")
    if _is_private_or_local_host(host):
        reasons.append("private_or_local_host")
    if bool(parsed.query):
        reasons.append("has_query_params")
    if parsed.port and parsed.port not in (80, 443):
        reasons.append("non_standard_port")
    if "@" in parsed.path:
        reasons.append("suspicious_path")
    if "private_or_local_host" in reasons:
        level = "high"
    elif "non_https" in reasons or "non_standard_port" in reasons:
        level = "medium"
    elif reasons:
        level = "low"
    else:
        level = "low"
    return {
        "host": host,
        "scheme": scheme,
        "risk_level": level,
        "risk_reasons": reasons,
    }


def _ensure_url(url: str) -> str:
    clean = (url or "").strip()
    if not (clean.startswith("https://") or clean.startswith("http://")):
        raise HTTPException(status_code=400, detail="URL must start with http:// or https://")
    if len(clean) > 2000:
        raise HTTPException(status_code=400, detail="URL is too long")
    parsed = urlparse(clean)
    host = (parsed.hostname or "").lower()
    if not host:
        raise HTTPException(status_code=400, detail="URL host is required")
    if parsed.username or parsed.password:
        raise HTTPException(status_code=400, detail="URL credentials are not allowed")
    if parsed.fragment:
        raise HTTPException(status_code=400, detail="URL fragments are not allowed")
    if bool(getattr(settings, "MINIAPP_BLOCK_PRIVATE_HOSTS", True)) and _is_private_or_local_host(host):
        raise HTTPException(status_code=400, detail="Local/private hosts are not allowed")
    if settings.MINIAPP_ALLOWED_HOSTS:
        allowed = set(settings.MINIAPP_ALLOWED_HOSTS)
        if not _host_allowed(host, allowed):
            raise HTTPException(status_code=400, detail="URL host is not allowed")
    elif settings.APP_ENV != "development" and parsed.scheme != "https":
        raise HTTPException(status_code=400, detail="Only https URLs are allowed in production")
    return clean


def _serialize_user(user: User) -> dict:
    from app.services.emoji_pack_service import preview_text_with_custom_emoji

    name = (user.name or "").strip()
    return {
        "id": user.id,
        "first_name": preview_text_with_custom_emoji(name) if name else "",
        "username": user.username or "",
    }


def _check_string(payload: dict) -> str:
    # Формат максимально близкий к Telegram initData verify string.
    pairs = []
    for key in sorted(payload.keys()):
        value = payload[key]
        if isinstance(value, (dict, list)):
            raw = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        else:
            raw = str(value)
        pairs.append(f"{key}={raw}")
    return "\n".join(pairs)


def _sign_payload(payload: dict, bot_token: str) -> str:
    # Привязываем подпись к bot_token и секрету приложения.
    key_seed = hashlib.sha256(f"{settings.SECRET_KEY}:{bot_token}".encode("utf-8")).digest()
    msg = _check_string(payload).encode("utf-8")
    return hmac.new(key_seed, msg, hashlib.sha256).hexdigest()


def _enforce_user_rate_limit(user_id: int, action: str, per_minute: int) -> None:
    if per_minute <= 0 or REDIS_IS_STUB:
        return
    redis = get_redis()
    key = f"miniapp:rl:{action}:u:{user_id}:m:{int(time.time() // 60)}"
    try:
        count = redis.incr(key)
        if count == 1:
            redis.expire(key, 70)
        if count > per_minute:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "MINIAPP_RATE_LIMIT_EXCEEDED",
                    "message": "Too many mini app requests. Please try again later.",
                    "action": action,
                },
                headers={"Retry-After": "60"},
            )
    except HTTPException:
        raise
    except Exception:
        # Не блокируем пользовательский запрос, если Redis недоступен.
        return


def _normalize_category(raw: Optional[str]) -> Optional[str]:
    value = (raw or "").strip().lower()
    if not value:
        return None
    if value not in MINIAPP_CATEGORIES:
        raise HTTPException(status_code=400, detail="bad_miniapp_category")
    return value


def _app_response(
    app: BotMiniApp,
    *,
    bot: User,
    installed: bool,
    is_owner: bool,
    last_launched_at=None,
) -> dict:
    url_risk = _url_risk_summary(app.url or "")
    icon_risk = _url_risk_summary(app.icon_url or "") if app.icon_url else None
    return {
        "id": app.id,
        "bot_id": app.bot_id,
        "bot_username": bot.bot_username or bot.username or "",
        "bot_name": bot.name,
        "name": app.name,
        "short_name": app.short_name,
        "description": app.description,
        "category": (getattr(app, "category", None) or None),
        "url": app.url,
        "icon_url": app.icon_url,
        "is_builtin": bool(app.is_builtin),
        "is_official": bool(app.is_official),
        "is_active": bool(app.is_active),
        "moderation_status": app.moderation_status or "pending",
        "moderation_note": app.moderation_note,
        "url_host": url_risk["host"],
        "url_scheme": url_risk["scheme"],
        "url_risk_level": url_risk["risk_level"],
        "url_risk_reasons": url_risk["risk_reasons"],
        "icon_url_host": icon_risk["host"] if icon_risk else None,
        "icon_url_risk_level": icon_risk["risk_level"] if icon_risk else None,
        "icon_url_risk_reasons": icon_risk["risk_reasons"] if icon_risk else [],
        "is_installed": installed,
        "is_owner": is_owner,
        "last_launched_at": last_launched_at,
        "created_at": app.created_at,
        "updated_at": app.updated_at,
    }


class MiniAppCreateRequest(BaseModel):
    bot_id: int
    name: str = Field(..., min_length=2, max_length=64)
    short_name: str = Field(..., min_length=2, max_length=32)
    description: Optional[str] = Field(None, max_length=512)
    category: Optional[str] = Field(None, max_length=32)
    url: str = Field(..., min_length=8, max_length=2000)
    icon_url: Optional[str] = Field(None, max_length=2000)


class MiniAppUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=64)
    description: Optional[str] = Field(None, max_length=512)
    category: Optional[str] = Field(None, max_length=32)
    url: Optional[str] = Field(None, min_length=8, max_length=2000)
    icon_url: Optional[str] = Field(None, max_length=2000)
    is_active: Optional[bool] = None


class MiniAppLaunchRequest(BaseModel):
    conversation_id: Optional[int] = None
    start_param: Optional[str] = Field(None, max_length=64)


class MiniAppSendDataRequest(BaseModel):
    """Telegram WebApp.sendData payload."""

    data: str = Field(..., min_length=1, max_length=4096)
    conversation_id: Optional[int] = None
    button_text: Optional[str] = Field(None, max_length=64)


class MiniAppVerifyInitDataRequest(BaseModel):
    init_data: str = Field(..., min_length=2, max_length=8192)


class MiniAppModerationRequest(BaseModel):
    moderation_status: str = Field(..., pattern="^(pending|approved|rejected)$")
    moderation_note: Optional[str] = Field(None, max_length=512)


def _can_user_access_non_approved_app(app: BotMiniApp, current_user: User, bot: User) -> bool:
    if current_user.is_admin:
        return True
    return bool(bot.created_by_user_id == current_user.id)


@router.get("/moderation/pending")
async def miniapps_moderation_queue(
    status_filter: Optional[str] = Query(
        None,
        alias="status",
        pattern="^(pending|approved|rejected)$",
    ),
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    query = db.query(BotMiniApp)
    if status_filter:
        query = query.filter(BotMiniApp.moderation_status == status_filter)
    else:
        query = query.filter(BotMiniApp.moderation_status.in_(["pending", "rejected"]))
    apps = query.order_by(BotMiniApp.updated_at.desc(), BotMiniApp.created_at.desc()).limit(200).all()
    bots = {
        b.id: b
        for b in db.query(User).filter(User.id.in_([a.bot_id for a in apps]), User.is_bot == True).all()
    }
    items = []
    for app in apps:
        bot = bots.get(app.bot_id)
        if not bot:
            continue
        is_owner = bool(bot.created_by_user_id == current_user.id)
        installed = (
            db.query(MiniAppInstall)
            .filter(MiniAppInstall.user_id == current_user.id, MiniAppInstall.miniapp_id == app.id)
            .first()
            is not None
        )
        items.append(_app_response(app, bot=bot, installed=installed, is_owner=is_owner))
    return {"items": items}


@router.get("/catalog")
async def miniapps_catalog(
    query: str = Query("", alias="q"),
    bot_username: Optional[str] = None,
    category: Optional[str] = None,
    only_installed: bool = False,
    sort: str = Query("default", pattern="^(default|recent|name)$"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    category_value = _normalize_category(category) if category else None
    # Community / publisher catalog only — archived kitchen builtins stay out.
    apps_q = db.query(BotMiniApp).filter(
        BotMiniApp.is_active == True,
        BotMiniApp.is_builtin == False,
    )
    if query.strip():
        q = f"%{query.strip()}%"
        apps_q = apps_q.filter(
            (BotMiniApp.name.ilike(q))
            | (BotMiniApp.short_name.ilike(q))
            | (BotMiniApp.description.ilike(q))
        )
    if category_value:
        apps_q = apps_q.filter(BotMiniApp.category == category_value)
    if bot_username:
        bot = db.query(User).filter(User.bot_username == bot_username, User.is_bot == True).first()
        if not bot:
            return {"items": [], "categories": list(MINIAPP_CATEGORIES)}
        apps_q = apps_q.filter(BotMiniApp.bot_id == bot.id)

    apps = apps_q.order_by(BotMiniApp.is_official.desc(), BotMiniApp.created_at.desc()).all()
    app_ids = [a.id for a in apps]
    installed_ids = set()
    launched_at_by_id = {}
    if app_ids:
        installs = (
            db.query(MiniAppInstall)
            .filter(
                MiniAppInstall.user_id == current_user.id,
                MiniAppInstall.miniapp_id.in_(app_ids),
            )
            .all()
        )
        installed_ids = {row.miniapp_id for row in installs}
        launched_at_by_id = {
            row.miniapp_id: row.last_launched_at for row in installs if row.last_launched_at
        }

    bots = {
        b.id: b
        for b in db.query(User).filter(User.id.in_([a.bot_id for a in apps]), User.is_bot == True).all()
    }
    items = []
    for app in apps:
        bot = bots.get(app.bot_id)
        if not bot:
            continue
        is_owner = bool(bot.created_by_user_id == current_user.id)
        if app.moderation_status != "approved" and not is_owner:
            continue
        is_installed = app.id in installed_ids
        if only_installed and not is_installed:
            continue
        items.append(
            _app_response(
                app,
                bot=bot,
                installed=is_installed,
                is_owner=is_owner,
                last_launched_at=launched_at_by_id.get(app.id),
            )
        )

    if sort == "recent":
        items.sort(
            key=lambda row: (
                row.get("last_launched_at") is None,
                -(row.get("last_launched_at").timestamp() if row.get("last_launched_at") else 0),
                not row.get("is_official", False),
                row.get("name") or "",
            )
        )
    elif sort == "name":
        items.sort(key=lambda row: (row.get("name") or "").lower())

    return {"items": items, "categories": list(MINIAPP_CATEGORIES)}


@router.get("/my")
async def list_my_miniapps(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bots = (
        db.query(User)
        .filter(User.created_by_user_id == current_user.id, User.is_bot == True)
        .all()
    )
    bot_map = {b.id: b for b in bots}
    if not bot_map:
        return {"items": []}
    apps = (
        db.query(BotMiniApp)
        .filter(BotMiniApp.bot_id.in_(list(bot_map.keys())))
        .order_by(BotMiniApp.created_at.desc())
        .all()
    )
    return {
        "items": [
            _app_response(app, bot=bot_map[app.bot_id], installed=False, is_owner=True)
            for app in apps
        ]
    }


@router.get("/by-bot/{bot_id}")
async def list_miniapps_by_bot(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")
    apps = (
        db.query(BotMiniApp)
        .filter(BotMiniApp.bot_id == bot_id)
        .order_by(BotMiniApp.created_at.desc())
        .all()
    )
    installed_ids = {
        row[0]
        for row in (
            db.query(MiniAppInstall.miniapp_id)
            .filter(
                MiniAppInstall.user_id == current_user.id,
                MiniAppInstall.miniapp_id.in_([a.id for a in apps] or [0]),
            )
            .all()
        )
    }
    return {
        "items": [
            _app_response(
                app,
                bot=bot,
                installed=app.id in installed_ids,
                is_owner=True,
            )
            for app in apps
        ]
    }


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_miniapp(
    payload: MiniAppCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == payload.bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")
    short_name = payload.short_name.strip().lower()
    if (
        not short_name.replace("_", "").replace("-", "").isalnum()
        or not short_name[0].isalnum()
        or not short_name[-1].isalnum()
    ):
        raise HTTPException(status_code=400, detail="short_name must be alphanumeric with _ or -")
    exists = (
        db.query(BotMiniApp)
        .filter(BotMiniApp.bot_id == bot.id, BotMiniApp.short_name == short_name)
        .first()
    )
    if exists:
        raise HTTPException(status_code=400, detail="Mini app short_name already exists for this bot")

    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens_http(
        current_user.id,
        payload.name,
        payload.description,
    )
    app = BotMiniApp(
        bot_id=bot.id,
        name=payload.name.strip(),
        short_name=short_name,
        description=(payload.description or "").strip() or None,
        category=_normalize_category(payload.category),
        url=_ensure_url(payload.url),
        icon_url=_ensure_url(payload.icon_url) if (payload.icon_url or "").strip() else None,
        moderation_status="approved" if current_user.is_admin else "pending",
    )
    db.add(app)
    db.commit()
    db.refresh(app)
    return _app_response(app, bot=bot, installed=False, is_owner=True)


@router.patch("/{miniapp_id}")
async def update_miniapp(
    miniapp_id: int,
    payload: MiniAppUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Access denied")

    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens_http(
        current_user.id,
        payload.name,
        payload.description,
    )
    requires_re_moderation = False
    if payload.name is not None:
        app.name = payload.name.strip()
        requires_re_moderation = True
    if payload.description is not None:
        app.description = payload.description.strip() or None
        requires_re_moderation = True
    if payload.category is not None:
        app.category = _normalize_category(payload.category)
    if payload.url is not None:
        app.url = _ensure_url(payload.url)
        requires_re_moderation = True
    if payload.icon_url is not None:
        app.icon_url = _ensure_url(payload.icon_url) if payload.icon_url.strip() else None
        requires_re_moderation = True
    if payload.is_active is not None:
        app.is_active = payload.is_active
    if requires_re_moderation and not current_user.is_admin:
        app.moderation_status = "pending"
        app.moderation_note = "Re-review required after update"
    db.commit()
    db.refresh(app)
    is_installed = (
        db.query(MiniAppInstall)
        .filter(MiniAppInstall.user_id == current_user.id, MiniAppInstall.miniapp_id == app.id)
        .first()
        is not None
    )
    return _app_response(app, bot=bot, installed=is_installed, is_owner=True)


@router.delete("/{miniapp_id}")
async def delete_miniapp(
    miniapp_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Access denied")
    db.delete(app)
    db.commit()
    return {"status": "ok"}


@router.post("/{miniapp_id}/install", status_code=status.HTTP_201_CREATED)
async def install_miniapp(
    miniapp_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id, BotMiniApp.is_active == True).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot:
        raise HTTPException(status_code=404, detail="Bot not found")
    if (
        bool(getattr(settings, "MINIAPP_REQUIRE_APPROVED_FOR_USE", True))
        and app.moderation_status != "approved"
        and not _can_user_access_non_approved_app(app, current_user, bot)
    ):
        raise HTTPException(status_code=403, detail="Mini app is not approved yet")
    install = (
        db.query(MiniAppInstall)
        .filter(MiniAppInstall.miniapp_id == miniapp_id, MiniAppInstall.user_id == current_user.id)
        .first()
    )
    if install:
        return {"status": "already_installed"}
    db.add(MiniAppInstall(miniapp_id=miniapp_id, user_id=current_user.id))
    db.commit()
    return {"status": "ok"}


@router.delete("/{miniapp_id}/install")
async def uninstall_miniapp(
    miniapp_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    deleted = (
        db.query(MiniAppInstall)
        .filter(MiniAppInstall.miniapp_id == miniapp_id, MiniAppInstall.user_id == current_user.id)
        .delete()
    )
    db.commit()
    if deleted == 0:
        return {"status": "not_installed"}
    return {"status": "ok"}


@router.post("/{miniapp_id}/launch-init-data")
async def launch_miniapp_init_data(
    miniapp_id: int,
    payload: MiniAppLaunchRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_user_rate_limit(
        current_user.id,
        action="launch",
        per_minute=int(settings.MINIAPP_LAUNCH_PER_MINUTE),
    )
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id, BotMiniApp.is_active == True).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot or not bot.bot_token:
        raise HTTPException(status_code=400, detail="Bot token is missing")
    if (
        bool(getattr(settings, "MINIAPP_REQUIRE_APPROVED_FOR_USE", True))
        and app.moderation_status != "approved"
        and not _can_user_access_non_approved_app(app, current_user, bot)
    ):
        raise HTTPException(status_code=403, detail="Mini app is not approved yet")

    auth_date = int(time.time())
    unsafe = {
        "query_id": f"miniapp-{miniapp_id}-{current_user.id}-{auth_date}",
        "user": _serialize_user(current_user),
        "auth_date": auth_date,
        "bot_id": app.bot_id,
        "miniapp_id": app.id,
    }
    if payload.start_param:
        unsafe["start_param"] = payload.start_param

    signature_payload = dict(unsafe)
    signature = _sign_payload(signature_payload, bot.bot_token)
    unsafe["hash"] = signature

    install = (
        db.query(MiniAppInstall)
        .filter(MiniAppInstall.miniapp_id == miniapp_id, MiniAppInstall.user_id == current_user.id)
        .first()
    )
    if install:
        install.last_launched_at = datetime.utcnow()
    else:
        # Opening an approved app counts as install (Telegram-like soft add).
        install = MiniAppInstall(
            miniapp_id=miniapp_id,
            user_id=current_user.id,
            last_launched_at=datetime.utcnow(),
        )
        db.add(install)
    db.add(
        MiniAppLaunch(
            miniapp_id=miniapp_id,
            user_id=current_user.id,
            conversation_id=payload.conversation_id,
        )
    )
    db.commit()

    return {
        "miniapp_id": app.id,
        "url": app.url,
        "init_data_unsafe": unsafe,
        "init_data": json.dumps(unsafe, ensure_ascii=False, separators=(",", ":")),
    }


@router.post("/{miniapp_id}/web-app-data")
async def send_miniapp_web_app_data(
    miniapp_id: int,
    payload: MiniAppSendDataRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Telegram-like WebApp.sendData: deliver data to the bot (webhook + chat message).
    """
    from app.models.conversation import ConversationMember, Message
    from app.services.bot_webhook_queue_service import enqueue_webhook_task
    from app.services.chat_event_bus import publish as publish_chat_event
    from app.services.user_event_bus import publish_user_event

    _enforce_user_rate_limit(
        current_user.id,
        action="web_app_data",
        per_minute=max(10, int(settings.MINIAPP_LAUNCH_PER_MINUTE)),
    )
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id, BotMiniApp.is_active == True).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot:
        raise HTTPException(status_code=400, detail="Bot not found")
    if (
        bool(getattr(settings, "MINIAPP_REQUIRE_APPROVED_FOR_USE", True))
        and app.moderation_status != "approved"
        and not _can_user_access_non_approved_app(app, current_user, bot)
    ):
        raise HTTPException(status_code=403, detail="Mini app is not approved yet")

    data = (payload.data or "").strip()
    if not data:
        raise HTTPException(status_code=400, detail="data is required")
    if len(data) > 4096:
        raise HTTPException(status_code=400, detail="data too long")

    conversation_id = payload.conversation_id
    if conversation_id is None:
        last_launch = (
            db.query(MiniAppLaunch)
            .filter(
                MiniAppLaunch.miniapp_id == miniapp_id,
                MiniAppLaunch.user_id == current_user.id,
                MiniAppLaunch.conversation_id.isnot(None),
            )
            .order_by(MiniAppLaunch.id.desc())
            .first()
        )
        if last_launch is not None:
            conversation_id = last_launch.conversation_id
    if conversation_id is None:
        # Fallback: open/find DM with the bot.
        from app.services.chat_service import ChatService

        try:
            conv = ChatService(db).get_or_create_direct(current_user.id, bot.id)
            conversation_id = conv.id
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="Cannot open bot chat") from exc

    member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == current_user.id,
        )
        .first()
    )
    if not member:
        raise HTTPException(status_code=403, detail="Access denied")
    bot_member = (
        db.query(ConversationMember)
        .filter(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == bot.id,
        )
        .first()
    )
    if not bot_member:
        raise HTTPException(status_code=400, detail="Bot is not in this chat")

    button_text = (payload.button_text or app.name or "Mini App").strip()[:64]
    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens_http(current_user.id, data, button_text)
    content = json.dumps(
        {
            "data": data,
            "button_text": button_text,
            "miniapp_id": app.id,
            "bot_id": bot.id,
        },
        ensure_ascii=False,
    )
    msg = Message(
        conversation_id=conversation_id,
        sender_id=current_user.id,
        type="web_app_data",
        content=content,
    )
    db.add(msg)
    db.flush()

    webhook_payload = {
        "conversation_id": conversation_id,
        "message_id": msg.id,
        "from_user_id": current_user.id,
        "bot_id": bot.id,
        "miniapp_id": app.id,
        "web_app_data": {
            "data": data,
            "button_text": button_text,
        },
    }
    enqueue_webhook_task(
        bot_id=bot.id,
        update_type="web_app_data",
        payload=webhook_payload,
    )
    db.commit()
    db.refresh(msg)

    message_event = {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_id": msg.sender_id,
        "type": msg.type,
        "content": msg.content,
        "media_url": None,
        "reply_to_message_id": None,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "is_paid": False,
        "price_stars": 0,
        "purchased": True,
        "reactions": [],
        "inline_keyboard": None,
    }
    publish_chat_event(
        conversation_id,
        {"type": "message.new", "message": message_event},
    )
    peer_ids = (
        db.query(ConversationMember.user_id)
        .filter(ConversationMember.conversation_id == conversation_id)
        .all()
    )
    for (uid,) in peer_ids:
        if uid == current_user.id:
            continue
        publish_user_event(
            uid,
            {"event": "chat.inbox", "conversation_id": conversation_id},
        )

    return {
        "ok": True,
        "message_id": msg.id,
        "conversation_id": conversation_id,
        "miniapp_id": app.id,
    }


@router.post("/{miniapp_id}/verify-init-data")
async def verify_miniapp_init_data(
    miniapp_id: int,
    payload: MiniAppVerifyInitDataRequest,
    current_user: Optional[User] = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id, BotMiniApp.is_active == True).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot or not bot.bot_token:
        raise HTTPException(status_code=400, detail="Bot token is missing")

    try:
        data = json.loads(payload.init_data)
    except Exception:
        raise HTTPException(status_code=400, detail="init_data must be valid JSON")
    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="init_data must be an object")
    provided_hash = str(data.get("hash") or "").strip()
    if not provided_hash:
        raise HTTPException(status_code=400, detail="init_data hash is required")
    auth_date_raw = data.get("auth_date")
    try:
        auth_date = int(auth_date_raw)
    except Exception:
        raise HTTPException(status_code=400, detail="init_data auth_date is invalid")
    now_ts = int(time.time())
    ttl = max(30, int(settings.MINIAPP_INITDATA_TTL_SECONDS))
    if auth_date > now_ts + 30:
        raise HTTPException(status_code=401, detail="init_data auth_date is in the future")
    if now_ts - auth_date > ttl:
        raise HTTPException(status_code=401, detail="init_data has expired")

    payload_miniapp_id = data.get("miniapp_id")
    payload_bot_id = data.get("bot_id")
    if str(payload_miniapp_id) != str(app.id):
        raise HTTPException(status_code=401, detail="init_data miniapp_id mismatch")
    if str(payload_bot_id) != str(app.bot_id):
        raise HTTPException(status_code=401, detail="init_data bot_id mismatch")

    user = data.get("user")
    if not isinstance(user, dict) or not user.get("id"):
        raise HTTPException(status_code=400, detail="init_data user is missing")
    try:
        payload_user_id = int(user.get("id"))
    except Exception:
        raise HTTPException(status_code=400, detail="init_data user.id is invalid")

    limiter_user_id = current_user.id if current_user is not None else payload_user_id
    _enforce_user_rate_limit(
        limiter_user_id,
        action="verify",
        per_minute=int(settings.MINIAPP_VERIFY_PER_MINUTE),
    )

    check_payload = dict(data)
    check_payload.pop("hash", None)
    expected_hash = _sign_payload(check_payload, bot.bot_token)
    valid = hmac.compare_digest(provided_hash, expected_hash)
    if not valid:
        raise HTTPException(status_code=401, detail="Invalid init_data signature")
    return {
        "ok": True,
        "miniapp_id": app.id,
        "bot_id": app.bot_id,
        "user": user,
        "auth_date": auth_date,
    }


@router.post("/{miniapp_id}/moderate")
async def moderate_miniapp(
    miniapp_id: int,
    payload: MiniAppModerationRequest,
    current_user: User = Depends(get_current_moderator_required),
    db: Session = Depends(get_db),
):
    from app.services.emoji_pack_service import EmojiPackService

    EmojiPackService(db).require_send_tokens_http(
        current_user.id,
        payload.moderation_note,
    )
    app = db.query(BotMiniApp).filter(BotMiniApp.id == miniapp_id).first()
    if not app:
        raise HTTPException(status_code=404, detail="Mini app not found")
    note = (payload.moderation_note or "").strip()
    if payload.moderation_status == "rejected" and len(note) < 5:
        raise HTTPException(
            status_code=400,
            detail="Rejection reason is required (min 5 chars)",
        )
    app.moderation_status = payload.moderation_status
    app.moderation_note = note or None
    if payload.moderation_status == "rejected":
        app.is_active = False
    elif payload.moderation_status == "approved":
        app.is_active = True
    db.commit()
    db.refresh(app)
    bot = db.query(User).filter(User.id == app.bot_id, User.is_bot == True).first()
    if not bot:
        raise HTTPException(status_code=404, detail="Bot not found")
    is_owner = bool(bot.created_by_user_id == current_user.id)
    installed = (
        db.query(MiniAppInstall)
        .filter(MiniAppInstall.user_id == current_user.id, MiniAppInstall.miniapp_id == app.id)
        .first()
        is not None
    )
    return _app_response(app, bot=bot, installed=installed, is_owner=is_owner)
