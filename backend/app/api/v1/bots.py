"""
API для управления ботами (BotFather)
"""
import secrets
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.bot_command import BotCommand

router = APIRouter(prefix="/bots", tags=["bots"])


# === Schemas ===

class BotCommandCreate(BaseModel):
    command: str = Field(..., min_length=1, max_length=32)
    description: str = Field(..., min_length=1, max_length=256)


class BotCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    username: str = Field(..., min_length=3, max_length=32)
    description: Optional[str] = Field(None, max_length=1000)
    short_description: Optional[str] = Field(None, max_length=120)
    commands: List[BotCommandCreate] = Field(default_factory=list)


class BotResponse(BaseModel):
    id: int
    name: str
    username: str
    bot_token: str
    description: Optional[str] = None
    short_description: Optional[str] = None
    avatar_url: Optional[str] = None


class BotListItem(BaseModel):
    id: int
    name: str
    username: str
    description: Optional[str] = None
    short_description: Optional[str] = None


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
    # Проверка уникальности username бота
    existing = db.query(User).filter(User.bot_username == payload.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Бот с таким username уже существует")

    # Генерация токена
    bot_token = secrets.token_urlsafe(32)

    # Создаём запись бота
    bot_user = User(
        email=f"bot+{payload.username}@haneat.internal",  # внутренний email
        password_hash="!",  # боты не логинятся по паролю
        name=payload.name,
        username=payload.username,
        is_bot=True,
        bot_token=bot_token,
        bot_username=payload.username,
        bot_description=payload.description,
        bot_short_description=payload.short_description,
        created_by_user_id=current_user.id,
    )
    db.add(bot_user)
    db.flush()  # получаем id

    # Сохраняем команды
    for cmd in payload.commands:
        db.add(BotCommand(
            bot_id=bot_user.id,
            command=cmd.command,
            description=cmd.description,
        ))

    db.commit()
    db.refresh(bot_user)

    return BotResponse(
        id=bot_user.id,
        name=bot_user.name,
        username=bot_user.bot_username,
        bot_token=bot_token,
        description=bot_user.bot_description,
        short_description=bot_user.bot_short_description,
        avatar_url=bot_user.avatar_url,
    )


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
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")
    return BotResponse(
        id=bot.id,
        name=bot.name,
        username=bot.bot_username,
        bot_token=bot.bot_token,
        description=bot.bot_description,
        short_description=bot.bot_short_description,
        avatar_url=bot.avatar_url,
    )


@router.patch("/{bot_id}", response_model=BotResponse)
async def update_bot(
    bot_id: int,
    payload: BotUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")

    if payload.name is not None:
        bot.name = payload.name
    if payload.description is not None:
        bot.bot_description = payload.description
    if payload.short_description is not None:
        bot.bot_short_description = payload.short_description

    db.commit()
    db.refresh(bot)
    return BotResponse(
        id=bot.id,
        name=bot.name,
        username=bot.bot_username,
        bot_token=bot.bot_token,
        description=bot.bot_description,
        short_description=bot.bot_short_description,
        avatar_url=bot.avatar_url,
    )


class WebhookSetRequest(BaseModel):
    url: Optional[str] = Field(None, max_length=500)
    secret_token: Optional[str] = Field(None, max_length=64)


@router.post("/{bot_id}/webhook")
async def set_webhook(
    bot_id: int,
    payload: WebhookSetRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")

    # Для MVP храним webhook в отдельных полях (добавьте колонки при необходимости)
    # bot.bot_webhook_url = payload.url
    # bot.bot_webhook_secret = payload.secret_token
    db.commit()
    return {"status": "ok", "webhook_url": payload.url}


@router.delete("/{bot_id}/webhook")
async def delete_webhook(
    bot_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found")
    # bot.bot_webhook_url = None
    db.commit()
    return {"status": "ok"}


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
    return [BotCommandCreate(command=c.command, description=c.description) for c in cmds]


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

    db.add(BotCommand(bot_id=bot_id, command=cmd.command, description=cmd.description))
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
