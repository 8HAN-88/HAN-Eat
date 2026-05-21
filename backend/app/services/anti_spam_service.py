"""
Ограничения для новых аккаунтов и подозрительной активности (V1).
"""
from datetime import datetime, timedelta
from typing import Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.comment import Comment
from app.models.post import Post
from app.models.user import User

NEW_ACCOUNT_HOURS = 24
NEW_ACCOUNT_MAX_POSTS = 3
NEW_ACCOUNT_MAX_COMMENTS = 10
BURST_POSTS_PER_HOUR = 15
BURST_COMMENTS_PER_HOUR = 30


class AntiSpamService:
    def __init__(self, db: Session):
        self.db = db

    def _is_new_account(self, user: User) -> bool:
        if not user.created_at:
            return True
        ref = user.created_at
        if getattr(ref, "tzinfo", None) is not None:
            ref = ref.replace(tzinfo=None)
        return (datetime.utcnow() - ref) < timedelta(hours=NEW_ACCOUNT_HOURS)

    def check_can_create_post(self, user: User) -> Tuple[bool, Optional[str]]:
        if user.is_admin or user.is_moderator:
            return True, None
        if float(user.trust_score or 0.5) < 0.2:
            return False, "Аккаунт ограничен. Обратитесь в поддержку."

        since_hour = datetime.utcnow() - timedelta(hours=1)
        hour_count = (
            self.db.query(func.count(Post.id))
            .filter(Post.user_id == user.id, Post.created_at >= since_hour)
            .scalar()
            or 0
        )
        if hour_count >= BURST_POSTS_PER_HOUR:
            return False, "Слишком много публикаций. Попробуйте позже."

        if self._is_new_account(user):
            since_day = datetime.utcnow() - timedelta(hours=NEW_ACCOUNT_HOURS)
            day_count = (
                self.db.query(func.count(Post.id))
                .filter(Post.user_id == user.id, Post.created_at >= since_day)
                .scalar()
                or 0
            )
            if day_count >= NEW_ACCOUNT_MAX_POSTS:
                return (
                    False,
                    f"Для новых аккаунтов: не более {NEW_ACCOUNT_MAX_POSTS} постов "
                    f"за первые {NEW_ACCOUNT_HOURS} ч.",
                )
        return True, None

    def check_can_create_comment(self, user: User) -> Tuple[bool, Optional[str]]:
        if user.is_admin or user.is_moderator:
            return True, None
        if float(user.trust_score or 0.5) < 0.2:
            return False, "Аккаунт ограничен."

        since_hour = datetime.utcnow() - timedelta(hours=1)
        hour_count = (
            self.db.query(func.count(Comment.id))
            .filter(Comment.user_id == user.id, Comment.created_at >= since_hour)
            .scalar()
            or 0
        )
        if hour_count >= BURST_COMMENTS_PER_HOUR:
            return False, "Слишком много комментариев. Попробуйте позже."

        if self._is_new_account(user):
            since_day = datetime.utcnow() - timedelta(hours=NEW_ACCOUNT_HOURS)
            day_count = (
                self.db.query(func.count(Comment.id))
                .filter(Comment.user_id == user.id, Comment.created_at >= since_day)
                .scalar()
                or 0
            )
            if day_count >= NEW_ACCOUNT_MAX_COMMENTS:
                return (
                    False,
                    f"Для новых аккаунтов: не более {NEW_ACCOUNT_MAX_COMMENTS} "
                    f"комментариев за первые {NEW_ACCOUNT_HOURS} ч.",
                )
        return True, None
