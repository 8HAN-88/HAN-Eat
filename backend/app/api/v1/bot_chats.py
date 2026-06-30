"""
API для добавления ботов в чаты и каналы
"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.conversation import Conversation, ConversationMember

router = APIRouter(prefix="/bots", tags=["Bots in chats"])


class AddBotToChatRequest(BaseModel):
    conversation_id: int


@router.post("/{bot_id}/add-to-chat", status_code=status.HTTP_201_CREATED)
async def add_bot_to_chat(
    bot_id: int,
    payload: AddBotToChatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Добавляет бота в указанный чат/канал.
    Только создатель бота может его добавлять.
    """
    # Проверяем, что бот существует и принадлежит текущему пользователю
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()
    if not bot or bot.created_by_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Bot not found or access denied")

    # Проверяем, что чат существует
    conv = db.query(Conversation).filter(Conversation.id == payload.conversation_id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Проверяем, что пользователь является участником чата (или владельцем канала)
    is_member = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == payload.conversation_id,
        ConversationMember.user_id == current_user.id,
    ).first()
    if not is_member:
        raise HTTPException(status_code=403, detail="You are not a member of this chat")

    # Проверяем, что бот ещё не в чате
    already_in = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == payload.conversation_id,
        ConversationMember.user_id == bot.id,
    ).first()
    if already_in:
        return {"status": "already_in_chat"}

    # Добавляем бота
    db.add(ConversationMember(conversation_id=payload.conversation_id, user_id=bot.id))
    db.commit()

    return {"status": "ok", "conversation_id": payload.conversation_id}
