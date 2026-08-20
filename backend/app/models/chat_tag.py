"""Per-user colored chat tags (Telegram Premium)."""

from sqlalchemy import (
    Column,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)

from app.core.database import Base


class ChatTag(Base):
    __tablename__ = "chat_tags"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title = Column(String(40), nullable=False)
    color = Column(String(16), nullable=False, default="blue")
    sort_order = Column(Integer, nullable=False, default=0)


class ConversationChatTag(Base):
    __tablename__ = "conversation_chat_tags"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    conversation_id = Column(
        Integer,
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    tag_id = Column(
        Integer, ForeignKey("chat_tags.id", ondelete="CASCADE"), nullable=False, index=True
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "conversation_id",
            "tag_id",
            name="uq_conversation_chat_tag",
        ),
    )
