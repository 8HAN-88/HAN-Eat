"""
Встроенный обработчик ботов (BotFather).
Обрабатывает входящие сообщения в чатах с ботами и генерирует автоматические ответы.
Также поддерживает inline-режим (@bot query) и callback-кнопки.
"""
import json
from typing import Optional, List, Dict, Any, Tuple
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.conversation import Message, ConversationMember
from app.models.bot_command import BotCommand
from app.models.miniapp import BotMiniApp
from app.services.analytics_service import AnalyticsService


def _text_for_bot_owner(db: Session, bot: User, text: Optional[str]) -> str:
    raw = (text or "").strip()
    if not raw:
        return raw
    owner_id = int(getattr(bot, "created_by_user_id", 0) or 0)
    if owner_id <= 0:
        return raw
    from app.services.emoji_pack_service import (
        EmojiPackService,
        keep_or_preview_tokens,
    )

    # Owner text copied into the chat as the bot — do not 403 the
    # peer, and do not truncate a long reply to 120 / «Сообщение».
    return keep_or_preview_tokens(EmojiPackService(db), owner_id, raw) or raw


def _keyboard_for_bot_owner(
    db: Session,
    bot: User,
    keyboard: Optional[List[List[Dict[str, Any]]]],
) -> Optional[List[List[Dict[str, Any]]]]:
    if not keyboard:
        return keyboard
    out: List[List[Dict[str, Any]]] = []
    for row in keyboard:
        if not isinstance(row, list):
            continue
        out_row: List[Dict[str, Any]] = []
        for btn in row:
            if not isinstance(btn, dict):
                continue
            clean = dict(btn)
            if clean.get("text"):
                clean["text"] = _text_for_bot_owner(db, bot, str(clean["text"]))
            if clean.get("callback_text"):
                clean["callback_text"] = _text_for_bot_owner(
                    db, bot, str(clean["callback_text"])
                )
            out_row.append(clean)
        if out_row:
            out.append(out_row)
    return out or None


def _find_bot_in_conversation(db: Session, conversation_id: int) -> Optional[User]:
    members = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == conversation_id
    ).all()
    for member in members:
        bot = db.query(User).filter(
            User.id == member.user_id,
            User.is_bot == True,
        ).first()
        if bot:
            return bot
    return None


def _bot_for_callback(db: Session, source_message: Message) -> Optional[User]:
    """Prefer the bot that sent the keyboard, not the first bot in the chat.

    Groups can have several bots. Old messages stay tappable after the bot
    leaves — look up the sender even if they are no longer a member.
    """
    sender = (
        db.query(User)
        .filter(User.id == source_message.sender_id, User.is_bot == True)
        .first()
    )
    if sender:
        return sender
    return _find_bot_in_conversation(db, source_message.conversation_id)


def _normalize_inline_buttons(raw: Any) -> Optional[List[List[Dict[str, Any]]]]:
    if not raw:
        return None
    source = raw
    if isinstance(raw, str):
        try:
            source = json.loads(raw)
        except Exception:
            return None
    if not isinstance(source, list):
        return None
    rows: List[List[Dict[str, Any]]] = []
    for row in source:
        if not isinstance(row, list):
            continue
        out_row: List[Dict[str, Any]] = []
        for btn in row:
            if not isinstance(btn, dict):
                continue
            text = str(btn.get("text") or "").strip()[:64]
            if not text:
                continue
            callback_data = btn.get("callback_data")
            url = btn.get("url")
            callback_text = btn.get("callback_text")
            miniapp_id = btn.get("miniapp_id")
            web_app = btn.get("web_app")
            clean: Dict[str, Any] = {"text": text}
            if isinstance(callback_data, str) and callback_data.strip():
                clean["callback_data"] = callback_data.strip()[:128]
            if isinstance(url, str) and url.strip():
                clean["url"] = url.strip()[:512]
            if isinstance(callback_text, str) and callback_text.strip():
                clean["callback_text"] = callback_text.strip()[:300]
            if miniapp_id is None and isinstance(web_app, dict):
                raw_id = web_app.get("miniapp_id") or web_app.get("id")
                try:
                    miniapp_id = int(raw_id) if raw_id is not None else None
                except Exception:
                    miniapp_id = None
                web_url = web_app.get("url")
                if isinstance(web_url, str) and web_url.strip() and "url" not in clean:
                    clean["url"] = web_url.strip()[:512]
            try:
                miniapp_id_int = int(miniapp_id) if miniapp_id is not None else None
            except Exception:
                miniapp_id_int = None
            if miniapp_id_int is not None and miniapp_id_int > 0:
                clean["miniapp_id"] = miniapp_id_int
                clean["web_app"] = {"miniapp_id": miniapp_id_int}
            if (
                "callback_data" not in clean
                and "url" not in clean
                and "miniapp_id" not in clean
            ):
                continue
            out_row.append(clean)
        if out_row:
            rows.append(out_row)
    return rows or None


def _button_callback_reply(
    keyboard: Optional[List[List[Dict[str, Any]]]],
    callback_data: str,
) -> Optional[str]:
    if not keyboard:
        return None
    for row in keyboard:
        for btn in row:
            if btn.get("callback_data") == callback_data:
                text = (btn.get("callback_text") or "").strip()
                if text:
                    return text[:300]
                label = (btn.get("text") or "").strip()
                if label:
                    return f"Нажата кнопка: {label}"
                return "Действие выполнено"
    return None


def get_inline_results(db: Session, bot_username: str, query: str, limit: int = 8) -> List[Dict[str, Any]]:
    """
    Возвращает результаты inline для бота по username и query.
    Для MVP возвращает список команд бота, которые содержат query.
    """
    bot = db.query(User).filter(User.bot_username == bot_username, User.is_bot == True).first()
    if not bot:
        return []

    q = query.lower().strip()
    cmds = db.query(BotCommand).filter(BotCommand.bot_id == bot.id).all()
    miniapps = (
        db.query(BotMiniApp)
        .filter(BotMiniApp.bot_id == bot.id, BotMiniApp.is_active == True)
        .all()
    )

    results: List[Dict[str, Any]] = []
    for cmd in cmds:
        if not q or q in cmd.command.lower() or q in cmd.description.lower():
            results.append({
                "type": "command",
                "id": f"cmd_{cmd.id}",
                "title": f"/{cmd.command}",
                "description": cmd.description,
                "payload": f"/{cmd.command}",
            })
            if len(results) >= limit:
                break

    if len(results) < limit:
        for app in miniapps:
            haystack = " ".join(
                [
                    (app.name or ""),
                    (app.short_name or ""),
                    (app.description or ""),
                ]
            ).lower()
            if q and q not in haystack:
                continue
            results.append({
                "type": "miniapp",
                "id": f"miniapp_{app.id}",
                "title": app.name,
                "description": app.description or f"Открыть {app.short_name}",
                "payload": f"/miniapp {app.id}",
                "miniapp_id": app.id,
                "miniapp_short_name": app.short_name,
            })
            if len(results) >= limit:
                break

    # Если ничего не найдено — показываем все команды
    if not results:
        for cmd in cmds[:limit]:
            results.append({
                "type": "command",
                "id": f"cmd_{cmd.id}",
                "title": f"/{cmd.command}",
                "description": cmd.description,
                "payload": f"/{cmd.command}",
            })
        if not results:
            for app in miniapps[:limit]:
                results.append({
                    "type": "miniapp",
                    "id": f"miniapp_{app.id}",
                    "title": app.name,
                    "description": app.description or f"Открыть {app.short_name}",
                    "payload": f"/miniapp {app.id}",
                    "miniapp_id": app.id,
                    "miniapp_short_name": app.short_name,
                })

    return results


def process_message_for_bot(db: Session, conversation_id: int, sender_id: int, content: str) -> Optional[Message]:
    """
    Проверяет, является ли получатель сообщения ботом.
    Если да — генерирует автоматический ответ бота (если сообщение — команда).
    Возвращает созданное сообщение бота или None.
    """
    bot = _find_bot_in_conversation(db, conversation_id)
    if not bot:
        return None

    # Обрабатываем только команды (начинаются с /)
    text = content.strip()
    if not text.startswith('/'):
        # Для MVP: если не команда — бот молчит или отвечает заглушкой
        return None

    command = text.split()[0].lstrip('/').lower()

    # Ищем кастомную команду
    cmd_row = db.query(BotCommand).filter(
        BotCommand.bot_id == bot.id,
        BotCommand.command == command
    ).first()

    reply_text: str
    inline_keyboard_json: Optional[str] = None
    reply_keyboard_update: Optional[dict] = None
    if cmd_row:
        reply_text = (cmd_row.response_text or "").strip() or cmd_row.description
        keyboard = _keyboard_for_bot_owner(
            db,
            bot,
            _normalize_inline_buttons(getattr(cmd_row, "inline_buttons_json", None)),
        )
        if keyboard:
            inline_keyboard_json = json.dumps(keyboard, ensure_ascii=False)
        from app.services.reply_keyboard_service import (
            normalize_reply_keyboard,
            set_member_reply_keyboard,
        )

        if bool(getattr(cmd_row, "remove_reply_keyboard", False)):
            set_member_reply_keyboard(
                db,
                conversation_id=conversation_id,
                user_id=sender_id,
                keyboard=None,
                remove=True,
            )
            reply_keyboard_update = {
                "reply_keyboard": None,
                "reply_keyboard_one_time": False,
                "reply_keyboard_resize": True,
                "reply_keyboard_placeholder": None,
                "remove_reply_keyboard": True,
            }
        else:
            reply_kb = _keyboard_for_bot_owner(
                db,
                bot,
                normalize_reply_keyboard(
                    getattr(cmd_row, "reply_buttons_json", None)
                ),
            )
            if reply_kb:
                one_time = bool(getattr(cmd_row, "reply_keyboard_one_time", False))
                resize = bool(getattr(cmd_row, "reply_keyboard_resize", True))
                placeholder = _text_for_bot_owner(
                    db,
                    bot,
                    getattr(cmd_row, "reply_keyboard_placeholder", None),
                )
                set_member_reply_keyboard(
                    db,
                    conversation_id=conversation_id,
                    user_id=sender_id,
                    keyboard=reply_kb,
                    one_time=one_time,
                    resize=resize,
                    placeholder=placeholder,
                )
                reply_keyboard_update = {
                    "reply_keyboard": reply_kb,
                    "reply_keyboard_one_time": one_time,
                    "reply_keyboard_resize": resize,
                    "reply_keyboard_placeholder": placeholder,
                    "remove_reply_keyboard": False,
                }
        AnalyticsService(db).log_event(
            event_type="bot_command_invoked",
            entity_type="bot",
            entity_id=bot.id,
            user_id=sender_id,
            author_id=bot.created_by_user_id,
            metadata={
                "command": command,
                "conversation_id": conversation_id,
            },
        )
    elif command == 'start':
        reply_text = bot.bot_short_description or f"Привет! Я {bot.name}. Чем могу помочь?"
    elif command == 'help':
        # Собираем список команд
        cmds = db.query(BotCommand).filter(BotCommand.bot_id == bot.id).all()
        if cmds:
            lines = [f"/{c.command} — {c.description}" for c in cmds]
            reply_text = "Доступные команды:\n" + "\n".join(lines)
        else:
            reply_text = "Доступные команды: /start, /help"
    else:
        reply_text = "Неизвестная команда. Напишите /help"

    reply_text = _text_for_bot_owner(db, bot, reply_text)

    # Создаём сообщение от имени бота
    bot_msg = Message(
        conversation_id=conversation_id,
        sender_id=bot.id,
        type="text",
        content=reply_text,
        inline_keyboard_json=inline_keyboard_json,
    )
    db.add(bot_msg)
    db.flush()
    if reply_keyboard_update is not None:
        # Attached for WS/API clients (not a DB column).
        setattr(bot_msg, "_reply_keyboard_update", reply_keyboard_update)
    return bot_msg


def process_callback_for_bot(
    db: Session,
    conversation_id: int,
    source_message: Message,
    callback_data: str,
) -> Optional[Tuple[Message, str]]:
    bot = _bot_for_callback(db, source_message)
    if not bot:
        return None
    keyboard = _normalize_inline_buttons(source_message.inline_keyboard_json)
    reply_text = _button_callback_reply(keyboard, callback_data.strip())
    if not reply_text:
        return None
    reply_text = _text_for_bot_owner(db, bot, reply_text)
    bot_msg = Message(
        conversation_id=conversation_id,
        sender_id=bot.id,
        type="text",
        content=reply_text,
    )
    db.add(bot_msg)
    db.flush()
    return bot_msg, "ok"
