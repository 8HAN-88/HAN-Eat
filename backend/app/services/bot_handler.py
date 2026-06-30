"""
Встроенный обработчик ботов (BotFather).
Обрабатывает входящие сообщения в чатах с ботами и генерирует автоматические ответы.
Также поддерживает inline-режим (@bot query).
"""
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.conversation import Message, ConversationMember
from app.models.bot_command import BotCommand


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

    return results


def process_message_for_bot(db: Session, conversation_id: int, sender_id: int, content: str) -> Optional[Message]:
    """
    Проверяет, является ли получатель сообщения ботом.
    Если да — генерирует автоматический ответ бота (если сообщение — команда).
    Возвращает созданное сообщение бота или None.
    """
    # Находим участников разговора
    members = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == conversation_id
    ).all()

    # Ищем бота среди участников (бот может быть в группе/канале)
    bot_member = next(
        (m for m in members if db.query(User).filter(User.id == m.user_id, User.is_bot == True).first()),
        None,
    )
    if not bot_member:
        return None

    bot = db.query(User).filter(User.id == bot_member.user_id, User.is_bot == True).first()
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
    if cmd_row:
        reply_text = cmd_row.description
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

    # Создаём сообщение от имени бота
    bot_msg = Message(
        conversation_id=conversation_id,
        sender_id=bot.id,
        type="text",
        content=reply_text,
    )
    db.add(bot_msg)
    db.flush()
    return bot_msg
