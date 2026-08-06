"""
API для управления ботами (BotFather)
"""
import json
import re
import secrets
from datetime import datetime
from typing import List, Optional
from urllib.parse import urlparse
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.dependencies import get_current_user_required as get_current_user
from app.models.user import User
from app.models.bot_command import BotCommand
from app.models.miniapp import BotMiniApp, MiniAppInstall, MiniAppLaunch
from app.services.analytics_service import AnalyticsService
from app.services.bot_webhook_service import deliver_webhook_update

router = APIRouter(prefix="/bots", tags=["bots"])


def _normalize_bot_username(raw: str) -> str:
    """Telegram BotFather rules: 5–32 chars, a-z/0-9/_, starts with letter, ends with bot."""
    value = (raw or "").strip().lstrip("@").lower()
    if not (5 <= len(value) <= 32):
        raise HTTPException(
            status_code=400,
            detail="Username must be 5–32 characters",
        )
    if not value.endswith("bot"):
        raise HTTPException(
            status_code=400,
            detail="Username must end with 'bot' (like Telegram)",
        )
    if not re.fullmatch(r"[a-z][a-z0-9_]*", value):
        raise HTTPException(
            status_code=400,
            detail="Username: start with a letter; only a-z, 0-9, underscore",
        )
    return value


def _bot_response(bot: User, *, token: Optional[str] = None) -> "BotResponse":
    return BotResponse(
        id=bot.id,
        name=bot.name,
        username=bot.bot_username or bot.username or "",
        bot_token=token if token is not None else (bot.bot_token or ""),
        description=bot.bot_description,
        short_description=bot.bot_short_description,
        avatar_url=bot.avatar_url,
        webhook_url=bot.bot_webhook_url,
        webhook_enabled=bool(bot.bot_webhook_enabled),
        webhook_last_error=bot.bot_webhook_last_error,
        webhook_last_ok_at=bot.bot_webhook_last_ok_at,
    )


# === Schemas ===

class BotReplyButton(BaseModel):
    text: str = Field(..., min_length=1, max_length=64)


class BotCommandCreate(BaseModel):
    command: str = Field(..., min_length=1, max_length=32)
    description: str = Field(..., min_length=1, max_length=256)
    response_text: Optional[str] = Field(None, max_length=2000)
    inline_buttons: Optional[List["BotInlineButton"]] = None
    inline_button_rows: Optional[List[List["BotInlineButton"]]] = None
    reply_buttons: Optional[List[BotReplyButton]] = None
    reply_button_rows: Optional[List[List[BotReplyButton]]] = None
    reply_keyboard_one_time: bool = False
    reply_keyboard_resize: bool = True
    reply_keyboard_placeholder: Optional[str] = Field(None, max_length=64)
    remove_reply_keyboard: bool = False


class BotInlineButton(BaseModel):
    text: str = Field(..., min_length=1, max_length=64)
    callback_data: Optional[str] = Field(None, max_length=128)
    url: Optional[str] = Field(None, max_length=512)
    callback_text: Optional[str] = Field(None, max_length=300)
    # Telegram WebApp button: open mini app by id (or nested {"url": "..."}).
    web_app: Optional[dict] = None
    miniapp_id: Optional[int] = Field(None, gt=0)


def _button_item_from_inline(btn: BotInlineButton) -> dict:
    item: dict = {"text": btn.text.strip()[:64]}
    if btn.callback_data and btn.callback_data.strip():
        item["callback_data"] = btn.callback_data.strip()[:128]
    if btn.url and btn.url.strip():
        item["url"] = btn.url.strip()[:512]
    if btn.callback_text and btn.callback_text.strip():
        item["callback_text"] = btn.callback_text.strip()[:300]
    miniapp_id = btn.miniapp_id
    if miniapp_id is None and isinstance(btn.web_app, dict):
        raw_id = btn.web_app.get("miniapp_id") or btn.web_app.get("id")
        try:
            miniapp_id = int(raw_id) if raw_id is not None else None
        except Exception:
            miniapp_id = None
        web_url = btn.web_app.get("url")
        if isinstance(web_url, str) and web_url.strip() and "url" not in item:
            item["url"] = web_url.strip()[:512]
    if miniapp_id is not None and int(miniapp_id) > 0:
        item["miniapp_id"] = int(miniapp_id)
        item["web_app"] = {"miniapp_id": int(miniapp_id)}
    if (
        "callback_data" not in item
        and "url" not in item
        and "miniapp_id" not in item
    ):
        raise HTTPException(
            status_code=400,
            detail="Each inline button requires callback_data, url, or web_app/miniapp_id",
        )
    return item


def _normalize_inline_buttons(
    buttons: Optional[List[BotInlineButton]],
    rows: Optional[List[List[BotInlineButton]]] = None,
) -> Optional[List[List[dict]]]:
    if rows:
        normalized_rows: List[List[dict]] = []
        for row_buttons in rows:
            row: List[dict] = []
            for btn in row_buttons:
                row.append(_button_item_from_inline(btn))
            if row:
                normalized_rows.append(row)
        return normalized_rows or None
    if not buttons:
        return None
    row = [_button_item_from_inline(btn) for btn in buttons]
    return [row] if row else None


def _normalize_reply_buttons(
    buttons: Optional[List[BotReplyButton]],
    rows: Optional[List[List[BotReplyButton]]] = None,
) -> Optional[List[List[dict]]]:
    from app.services.reply_keyboard_service import normalize_reply_keyboard

    if rows:
        raw = [
            [{"text": b.text} for b in row_buttons if b.text and b.text.strip()]
            for row_buttons in rows
        ]
        return normalize_reply_keyboard(raw)
    if not buttons:
        return None
    return normalize_reply_keyboard([[{"text": b.text} for b in buttons]])


class BotCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    username: str = Field(..., min_length=3, max_length=32)
    description: Optional[str] = Field(None, max_length=1000)
    short_description: Optional[str] = Field(None, max_length=120)
    commands: List[BotCommandCreate] = Field(default_factory=list)


BotCommandCreate.model_rebuild()


class BotResponse(BaseModel):
    id: int
    name: str
    username: str
    bot_token: str
    description: Optional[str] = None
    short_description: Optional[str] = None
    avatar_url: Optional[str] = None
    webhook_url: Optional[str] = None
    webhook_enabled: bool = False
    webhook_last_error: Optional[str] = None
    webhook_last_ok_at: Optional[datetime] = None


class BotListItem(BaseModel):
    id: int
    name: str
    username: str
    description: Optional[str] = None
    short_description: Optional[str] = None


def _bot_or_404(db: Session, bot_id: int, owner_id: int) -> User:
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != owner_id:
        raise HTTPException(status_code=404, detail="Bot not found")
    return bot


def _validate_webhook_url(url: str) -> str:
    clean = (url or "").strip()
    parsed = urlparse(clean)
    if parsed.scheme not in ("http", "https"):
        raise HTTPException(status_code=400, detail="Webhook URL must start with http/https")
    if not parsed.netloc:
        raise HTTPException(status_code=400, detail="Webhook URL host is required")
    return clean


# === Endpoints ===

@router.post("/create", response_model=BotResponse, status_code=status.HTTP_201_CREATED)
async def create_bot(
    payload: BotCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Создание нового бота (аналог @BotFather).
    Пользователь получает токен один раз — его нужно сохранить сразу.
    """
    username = _normalize_bot_username(payload.username)
    existing = db.query(User).filter(User.bot_username == username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Бот с таким username уже существует")

    # Генерация токена
    bot_token = secrets.token_urlsafe(32)

    # Создаём запись бота
    bot_user = User(
        email=f"bot+{username}@haneat.internal",  # внутренний email
        password_hash="!",  # боты не логинятся по паролю
        name=payload.name.strip(),
        username=username,
        is_bot=True,
        bot_token=bot_token,
        bot_username=username,
        bot_description=payload.description,
        bot_short_description=payload.short_description,
        created_by_user_id=current_user.id,
    )
    db.add(bot_user)
    db.flush()  # получаем id

    # Как у Telegram-ботов: /start и /help есть с рождения, если клиент не передал свои.
    provided = {
        (c.command or "").strip().lstrip("/").lower()
        for c in payload.commands
        if (c.command or "").strip()
    }
    seed_commands: List[BotCommandCreate] = []
    if "start" not in provided:
        seed_commands.append(
            BotCommandCreate(
                command="start",
                description="Start the bot",
                response_text=f"Hi! I'm {bot_user.name}. Use /help to see commands.",
            )
        )
    if "help" not in provided:
        seed_commands.append(
            BotCommandCreate(
                command="help",
                description="Show help",
                response_text=f"Commands for @{username}: /start, /help",
            )
        )

    for cmd in list(seed_commands) + list(payload.commands):
        inline_buttons = _normalize_inline_buttons(
            cmd.inline_buttons,
            cmd.inline_button_rows,
        )
        reply_buttons = _normalize_reply_buttons(
            cmd.reply_buttons,
            cmd.reply_button_rows,
        )
        command_name = (cmd.command or "").strip().lstrip("/").lower()
        if not command_name:
            continue
        db.add(BotCommand(
            bot_id=bot_user.id,
            command=command_name,
            description=cmd.description,
            response_text=cmd.response_text.strip()[:2000] if cmd.response_text else None,
            inline_buttons_json=json.dumps(inline_buttons, ensure_ascii=False) if inline_buttons else None,
            reply_buttons_json=json.dumps(reply_buttons, ensure_ascii=False) if reply_buttons else None,
            reply_keyboard_one_time=bool(cmd.reply_keyboard_one_time),
            reply_keyboard_resize=bool(cmd.reply_keyboard_resize),
            reply_keyboard_placeholder=(
                (cmd.reply_keyboard_placeholder or "").strip()[:64] or None
            ),
            remove_reply_keyboard=bool(cmd.remove_reply_keyboard),
        ))

    db.commit()
    db.refresh(bot_user)

    return _bot_response(bot_user, token=bot_token)


@router.get("/my", response_model=List[BotListItem])
async def list_my_bots(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Список ботов, созданных текущим пользователем"""
    bots = db.query(User).filter(
        User.created_by_user_id == current_user.id,
        User.is_bot == True
    ).all()

    return [
        BotListItem(
            id=b.id,
            name=b.name,
            username=b.bot_username,
            description=b.bot_description,
            short_description=b.bot_short_description,
        )
        for b in bots
    ]


class BotUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, max_length=64)
    description: Optional[str] = Field(None, max_length=1000)
    short_description: Optional[str] = Field(None, max_length=120)


@router.get("/{bot_id}", response_model=BotResponse)
async def get_bot(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)
    return _bot_response(bot)


@router.patch("/{bot_id}", response_model=BotResponse)
async def update_bot(
    bot_id: int,
    payload: BotUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)

    if payload.name is not None:
        bot.name = payload.name.strip() or bot.name
    if payload.description is not None:
        bot.bot_description = payload.description.strip() or None
    if payload.short_description is not None:
        bot.bot_short_description = payload.short_description.strip() or None

    db.commit()
    db.refresh(bot)
    return _bot_response(bot)


@router.post("/{bot_id}/token/revoke", response_model=BotResponse)
async def revoke_bot_token(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Как /revoke в @BotFather — выдаёт новый токен, старый перестаёт работать."""
    bot = _bot_or_404(db, bot_id, current_user.id)
    new_token = secrets.token_urlsafe(32)
    bot.bot_token = new_token
    db.commit()
    db.refresh(bot)
    return _bot_response(bot, token=new_token)


@router.delete("/{bot_id}", status_code=status.HTTP_200_OK)
async def delete_bot(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Удаление бота вместе с командами и мини-приложениями (как /deletebot)."""
    bot = _bot_or_404(db, bot_id, current_user.id)
    app_ids = [
        row.id
        for row in db.query(BotMiniApp.id).filter(BotMiniApp.bot_id == bot.id).all()
    ]
    if app_ids:
        db.query(MiniAppInstall).filter(MiniAppInstall.miniapp_id.in_(app_ids)).delete(
            synchronize_session=False
        )
        db.query(MiniAppLaunch).filter(MiniAppLaunch.miniapp_id.in_(app_ids)).delete(
            synchronize_session=False
        )
        db.query(BotMiniApp).filter(BotMiniApp.bot_id == bot.id).delete(
            synchronize_session=False
        )
    db.query(BotCommand).filter(BotCommand.bot_id == bot.id).delete(
        synchronize_session=False
    )
    db.delete(bot)
    db.commit()
    return {"status": "ok"}


class WebhookSetRequest(BaseModel):
    url: Optional[str] = Field(None, max_length=500)
    secret_token: Optional[str] = Field(None, max_length=64)
    verify_delivery: bool = True


@router.post("/{bot_id}/webhook")
async def set_webhook(
    bot_id: int,
    payload: WebhookSetRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)
    if not payload.url:
        raise HTTPException(status_code=400, detail="Webhook URL is required")
    bot.bot_webhook_url = _validate_webhook_url(payload.url)
    bot.bot_webhook_secret = (payload.secret_token or "").strip()[:128] or None
    bot.bot_webhook_enabled = True
    bot.bot_webhook_last_error = None
    if payload.verify_delivery:
        deliver_webhook_update(
            db,
            bot_user=bot,
            update_type="webhook.verify",
            delivery_id=secrets.token_hex(12),
            payload={
                "bot_id": bot.id,
                "bot_username": bot.bot_username,
                "verified_at": datetime.utcnow().isoformat(),
            },
        )
    db.commit()
    return {
        "status": "ok",
        "webhook_url": bot.bot_webhook_url,
        "webhook_enabled": True,
        "webhook_last_error": bot.bot_webhook_last_error,
        "webhook_last_ok_at": bot.bot_webhook_last_ok_at,
    }


@router.delete("/{bot_id}/webhook")
async def delete_webhook(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)
    bot.bot_webhook_url = None
    bot.bot_webhook_secret = None
    bot.bot_webhook_enabled = False
    bot.bot_webhook_last_error = None
    bot.bot_webhook_last_ok_at = None
    db.commit()
    return {"status": "ok"}


@router.get("/{bot_id}/webhook")
async def get_webhook(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)
    return {
        "webhook_url": bot.bot_webhook_url,
        "webhook_enabled": bool(bot.bot_webhook_enabled),
        "webhook_last_error": bot.bot_webhook_last_error,
        "webhook_last_ok_at": bot.bot_webhook_last_ok_at,
    }


@router.post("/{bot_id}/webhook/test")
async def test_webhook_delivery(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = _bot_or_404(db, bot_id, current_user.id)
    if not bot.bot_webhook_enabled or not bot.bot_webhook_url:
        raise HTTPException(
            status_code=400,
            detail="Webhook is not configured or disabled",
        )

    delivered = deliver_webhook_update(
        db,
        bot_user=bot,
        update_type="webhook.test",
        delivery_id=secrets.token_hex(12),
        payload={
            "bot_id": bot.id,
            "bot_username": bot.bot_username,
            "triggered_by_user_id": current_user.id,
            "triggered_at": datetime.utcnow().isoformat(),
            "source": "manual_test",
        },
    )
    db.commit()
    return {
        "status": "ok" if delivered else "failed",
        "delivered": delivered,
        "webhook_last_error": bot.bot_webhook_last_error,
        "webhook_last_ok_at": bot.bot_webhook_last_ok_at,
    }


# === Управление командами бота ===

@router.get("/{bot_id}/commands", response_model=List[BotCommandCreate])
async def list_bot_commands(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")

    cmds = db.query(BotCommand).filter(BotCommand.bot_id == bot_id).all()
    result: List[BotCommandCreate] = []
    for c in cmds:
        inline_button_rows: List[List[BotInlineButton]] = []
        if c.inline_buttons_json:
            try:
                parsed = json.loads(c.inline_buttons_json)
                if isinstance(parsed, list):
                    for row in parsed:
                        if not isinstance(row, list):
                            continue
                        out_row: List[BotInlineButton] = []
                        for btn in row:
                            if not isinstance(btn, dict):
                                continue
                            text = str(btn.get("text") or "").strip()
                            if not text:
                                continue
                            out_row.append(
                                BotInlineButton(
                                    text=text,
                                    callback_data=btn.get("callback_data"),
                                    url=btn.get("url"),
                                    callback_text=btn.get("callback_text"),
                                )
                            )
                        if out_row:
                            inline_button_rows.append(out_row)
            except Exception:
                inline_button_rows = []
        reply_button_rows: List[List[BotReplyButton]] = []
        if getattr(c, "reply_buttons_json", None):
            try:
                parsed = json.loads(c.reply_buttons_json)
                if isinstance(parsed, list):
                    for row in parsed:
                        if not isinstance(row, list):
                            continue
                        out_row: List[BotReplyButton] = []
                        for btn in row:
                            text = ""
                            if isinstance(btn, dict):
                                text = str(btn.get("text") or "").strip()
                            elif isinstance(btn, str):
                                text = btn.strip()
                            if text:
                                out_row.append(BotReplyButton(text=text))
                        if out_row:
                            reply_button_rows.append(out_row)
            except Exception:
                reply_button_rows = []
        result.append(
            BotCommandCreate(
                command=c.command,
                description=c.description,
                response_text=c.response_text,
                inline_button_rows=inline_button_rows or None,
                inline_buttons=(inline_button_rows[0] if len(inline_button_rows) == 1 else None),
                reply_button_rows=reply_button_rows or None,
                reply_buttons=(reply_button_rows[0] if len(reply_button_rows) == 1 else None),
                reply_keyboard_one_time=bool(getattr(c, "reply_keyboard_one_time", False)),
                reply_keyboard_resize=bool(getattr(c, "reply_keyboard_resize", True)),
                reply_keyboard_placeholder=getattr(c, "reply_keyboard_placeholder", None),
                remove_reply_keyboard=bool(getattr(c, "remove_reply_keyboard", False)),
            )
        )
    return result


@router.post("/{bot_id}/commands", status_code=status.HTTP_201_CREATED)
async def add_bot_command(
    bot_id: int,
    cmd: BotCommandCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")

    # Проверка дубликата
    existing = db.query(BotCommand).filter(
        BotCommand.bot_id == bot_id,
        BotCommand.command == cmd.command
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Command already exists")

    inline_buttons = _normalize_inline_buttons(
        cmd.inline_buttons,
        cmd.inline_button_rows,
    )
    reply_buttons = _normalize_reply_buttons(
        cmd.reply_buttons,
        cmd.reply_button_rows,
    )
    db.add(
        BotCommand(
            bot_id=bot_id,
            command=cmd.command,
            description=cmd.description,
            response_text=cmd.response_text.strip()[:2000] if cmd.response_text else None,
            inline_buttons_json=json.dumps(inline_buttons, ensure_ascii=False) if inline_buttons else None,
            reply_buttons_json=json.dumps(reply_buttons, ensure_ascii=False) if reply_buttons else None,
            reply_keyboard_one_time=bool(cmd.reply_keyboard_one_time),
            reply_keyboard_resize=bool(cmd.reply_keyboard_resize),
            reply_keyboard_placeholder=(
                (cmd.reply_keyboard_placeholder or "").strip()[:64] or None
            ),
            remove_reply_keyboard=bool(cmd.remove_reply_keyboard),
        )
    )
    db.commit()
    return {"status": "ok"}


class BotCommandUpdateRequest(BaseModel):
    description: Optional[str] = Field(None, min_length=1, max_length=256)
    response_text: Optional[str] = Field(None, max_length=2000)
    inline_buttons: Optional[List["BotInlineButton"]] = None
    inline_button_rows: Optional[List[List["BotInlineButton"]]] = None
    clear_inline_buttons: bool = False
    reply_buttons: Optional[List[BotReplyButton]] = None
    reply_button_rows: Optional[List[List[BotReplyButton]]] = None
    clear_reply_buttons: bool = False
    reply_keyboard_one_time: Optional[bool] = None
    reply_keyboard_resize: Optional[bool] = None
    reply_keyboard_placeholder: Optional[str] = Field(None, max_length=64)
    remove_reply_keyboard: Optional[bool] = None


BotCommandUpdateRequest.model_rebuild()


@router.patch("/{bot_id}/commands/{command}")
async def update_bot_command(
    bot_id: int,
    command: str,
    payload: BotCommandUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")
    cmd = db.query(BotCommand).filter(
        BotCommand.bot_id == bot_id,
        BotCommand.command == command,
    ).first()
    if not cmd:
        raise HTTPException(status_code=404, detail="Command not found")
    if payload.description is not None:
        cmd.description = payload.description.strip()
    if payload.response_text is not None:
        cmd.response_text = payload.response_text.strip()[:2000] or None
    if payload.clear_inline_buttons:
        cmd.inline_buttons_json = None
    elif payload.inline_button_rows is not None or payload.inline_buttons is not None:
        inline_buttons = _normalize_inline_buttons(
            payload.inline_buttons,
            payload.inline_button_rows,
        )
        cmd.inline_buttons_json = (
            json.dumps(inline_buttons, ensure_ascii=False) if inline_buttons else None
        )
    if payload.clear_reply_buttons:
        cmd.reply_buttons_json = None
    elif payload.reply_button_rows is not None or payload.reply_buttons is not None:
        reply_buttons = _normalize_reply_buttons(
            payload.reply_buttons,
            payload.reply_button_rows,
        )
        cmd.reply_buttons_json = (
            json.dumps(reply_buttons, ensure_ascii=False) if reply_buttons else None
        )
    if payload.reply_keyboard_one_time is not None:
        cmd.reply_keyboard_one_time = bool(payload.reply_keyboard_one_time)
    if payload.reply_keyboard_resize is not None:
        cmd.reply_keyboard_resize = bool(payload.reply_keyboard_resize)
    if payload.reply_keyboard_placeholder is not None:
        cmd.reply_keyboard_placeholder = (
            payload.reply_keyboard_placeholder.strip()[:64] or None
        )
    if payload.remove_reply_keyboard is not None:
        cmd.remove_reply_keyboard = bool(payload.remove_reply_keyboard)
    db.commit()
    return {"status": "ok"}


@router.delete("/{bot_id}/commands/{command}")
async def delete_bot_command(
    bot_id: int,
    command: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")

    deleted = db.query(BotCommand).filter(
        BotCommand.bot_id == bot_id,
        BotCommand.command == command
    ).delete()
    db.commit()
    if deleted == 0:
        raise HTTPException(status_code=404, detail="Command not found")
    return {"status": "ok"}


@router.get("/{bot_id}/analytics")
async def get_bot_analytics(
    bot_id: int,
    days: int = 30,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _bot_or_404(db, bot_id, current_user.id)
    data = AnalyticsService(db).get_bot_analytics(
        bot_id=bot_id,
        owner_user_id=current_user.id,
        days=max(1, min(int(days), 365)),
    )
    if data.get("error"):
        raise HTTPException(status_code=404, detail=data["error"])
    return data


@router.get("/{bot_id}/webhook/attempts")
async def get_bot_webhook_attempts(
    bot_id: int,
    limit: int = 30,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _bot_or_404(db, bot_id, current_user.id)
    data = AnalyticsService(db).get_bot_webhook_attempts(
        bot_id=bot_id,
        owner_user_id=current_user.id,
        limit=max(1, min(int(limit), 100)),
    )
    if data.get("error"):
        raise HTTPException(status_code=404, detail=data["error"])
    return data


# === Inline Mode ===

@router.get("/inline")
async def inline_query(
    bot: str,
    query: str = "",
    limit: int = 8,
    db: Session = Depends(get_db),
):
    """
    Inline-режим: GET /api/v1/bots/inline?bot=weather_bot&query=москва
    Возвращает список результатов (команды, мини-приложения и т.д.)
    """
    from app.services.bot_handler import get_inline_results
    results = get_inline_results(db, bot, query, limit=limit)
    return {"results": results}
