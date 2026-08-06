"""
Сервис для аналитики
"""
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from app.models.analytics_event import AnalyticsEvent
from app.models.post import Post
from app.models.user import User
from app.models.follower import Follower
from app.models.community_member import ChannelMember
from app.models.conversation import Message


class AnalyticsService:
    """Сервис для работы с аналитикой"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def log_event(
        self,
        event_type: str,
        entity_type: str,
        entity_id: int,
        user_id: Optional[int] = None,
        author_id: Optional[int] = None,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """Логировать событие"""
        event = AnalyticsEvent(
            event_type=event_type,
            entity_type=entity_type,
            entity_id=entity_id,
            user_id=user_id,
            author_id=author_id,
            event_metadata=metadata or {}
        )
        self.db.add(event)
        # Не коммитим здесь, чтобы можно было батчить события
    
    def get_post_analytics(
        self,
        post_id: int,
        author_id: int,
        days: int = 30
    ) -> Dict[str, Any]:
        """Получить аналитику поста"""
        # Проверяем, что пользователь является автором
        post = self.db.query(Post).filter(
            Post.id == post_id,
            Post.user_id == author_id
        ).first()
        
        if not post:
            return {"error": "Post not found or access denied"}
        
        start_date = datetime.utcnow() - timedelta(days=days)
        
        # Общие метрики
        total_views = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        unique_views = self.db.query(func.count(func.distinct(AnalyticsEvent.user_id))).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        # Вовлеченность
        likes = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "like",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        comments = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "comment",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        saves = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "save",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        reposts = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "repost",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        clicks = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "click",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        # CTR (Click-Through Rate)
        ctr = (clicks / total_views * 100) if total_views > 0 else 0
        
        # Вовлеченность (Engagement Rate)
        engagement = ((likes + comments + saves + reposts) / total_views * 100) if total_views > 0 else 0
        
        # Статистика по дням
        daily_stats = self._get_daily_stats(post_id, "post", start_date)
        
        return {
            "post_id": post_id,
            "period_days": days,
            "views": {
                "total": total_views,
                "unique": unique_views,
            },
            "engagement": {
                "likes": likes,
                "comments": comments,
                "saves": saves,
                "reposts": reposts,
                "total": likes + comments + saves + reposts,
                "rate": round(engagement, 2),
            },
            "metrics": {
                "ctr": round(ctr, 2),  # Click-Through Rate в процентах
                "engagement_rate": round(engagement, 2),
            },
            "by_day": daily_stats,
        }
    
    def _followers_count(self, user_id: int) -> int:
        return int(
            self.db.query(func.count(Follower.id))
            .filter(Follower.followee_id == user_id)
            .scalar() or 0
        )

    def _channels_count(self, user_id: int) -> int:
        return int(
            self.db.query(func.count(func.distinct(ChannelMember.channel_id)))
            .filter(ChannelMember.user_id == user_id)
            .scalar() or 0
        )

    def _engagement_by_post(
        self,
        post_ids: List[int],
        start_date: datetime,
    ) -> Dict[int, Dict[str, int]]:
        """Счётчики like/comment/save/repost по постам за период."""
        if not post_ids:
            return {}
        rows = self.db.query(
            AnalyticsEvent.entity_id,
            AnalyticsEvent.event_type,
            func.count(AnalyticsEvent.id),
        ).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type.in_(["like", "comment", "save", "repost"]),
            AnalyticsEvent.created_at >= start_date,
        ).group_by(
            AnalyticsEvent.entity_id,
            AnalyticsEvent.event_type,
        ).all()
        out: Dict[int, Dict[str, int]] = {}
        for entity_id, event_type, cnt in rows:
            bucket = out.setdefault(int(entity_id), {})
            bucket[str(event_type)] = int(cnt)
        return out

    def get_profile_analytics(
        self,
        user_id: int,
        days: int = 30
    ) -> Dict[str, Any]:
        """Получить аналитику профиля"""
        start_date = datetime.utcnow() - timedelta(days=days)
        followers_count = self._followers_count(user_id)
        channels_count = self._channels_count(user_id)

        # Общие метрики по всем постам пользователя
        posts = self.db.query(Post.id).filter(
            Post.user_id == user_id,
            Post.status == "published",
            Post.deleted_at.is_(None)
        ).all()
        post_ids = [p[0] for p in posts]

        if not post_ids:
            return {
                "user_id": user_id,
                "period_days": days,
                "posts_count": 0,
                "followers_count": followers_count,
                "channels_count": channels_count,
                "total_views": 0,
                "total_engagement": {
                    "likes": 0,
                    "comments": 0,
                    "saves": 0,
                    "reposts": 0,
                    "total": 0,
                },
                "engagement_rate": 0.0,
                "top_posts": [],
                "by_day": [],
            }
        
        # Общее количество просмотров
        total_views = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        # Общая вовлеченность
        total_likes = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "like",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        total_comments = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "comment",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        total_saves = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "save",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0
        
        total_reposts = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "repost",
            AnalyticsEvent.created_at >= start_date
        ).scalar() or 0

        engagement_total = (
            int(total_likes) + int(total_comments) + int(total_saves) + int(total_reposts)
        )
        engagement_rate = (
            round(engagement_total / int(total_views) * 100, 2)
            if int(total_views) > 0
            else 0.0
        )

        # Топ постов по просмотрам
        top_posts = self._get_top_posts(post_ids, start_date, limit=10)
        
        # Статистика по дням
        daily_stats = self._get_daily_stats_for_posts(post_ids, start_date)
        
        return {
            "user_id": user_id,
            "period_days": days,
            "posts_count": len(post_ids),
            "followers_count": followers_count,
            "channels_count": channels_count,
            "total_views": total_views,
            "total_engagement": {
                "likes": total_likes,
                "comments": total_comments,
                "saves": total_saves,
                "reposts": total_reposts,
                "total": engagement_total,
            },
            "engagement_rate": engagement_rate,
            "top_posts": top_posts,
            "by_day": daily_stats,
        }
    
    def _get_daily_stats(
        self,
        entity_id: int,
        entity_type: str,
        start_date: datetime
    ) -> List[Dict[str, Any]]:
        """Получить статистику по дням для одной сущности"""
        # Группируем по дням
        daily = self.db.query(
            func.date(AnalyticsEvent.created_at).label('date'),
            func.count(AnalyticsEvent.id).label('count')
        ).filter(
            AnalyticsEvent.entity_type == entity_type,
            AnalyticsEvent.entity_id == entity_id,
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).group_by(
            func.date(AnalyticsEvent.created_at)
        ).order_by(
            func.date(AnalyticsEvent.created_at)
        ).all()
        
        return [
            {
                "date": row.date.isoformat() if row.date else None,
                "count": row.count,
            }
            for row in daily
        ]
    
    def _get_daily_stats_for_posts(
        self,
        post_ids: List[int],
        start_date: datetime
    ) -> List[Dict[str, Any]]:
        """Получить статистику по дням для нескольких постов"""
        daily = self.db.query(
            func.date(AnalyticsEvent.created_at).label('date'),
            func.count(AnalyticsEvent.id).label('count')
        ).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).group_by(
            func.date(AnalyticsEvent.created_at)
        ).order_by(
            func.date(AnalyticsEvent.created_at)
        ).all()
        
        return [
            {
                "date": row.date.isoformat() if row.date else None,
                "count": row.count,
            }
            for row in daily
        ]
    
    def _get_top_posts(
        self,
        post_ids: List[int],
        start_date: datetime,
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """Получить топ постов по просмотрам"""
        top = self.db.query(
            AnalyticsEvent.entity_id,
            func.count(AnalyticsEvent.id).label('views')
        ).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id.in_(post_ids),
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= start_date
        ).group_by(
            AnalyticsEvent.entity_id
        ).order_by(
            func.count(AnalyticsEvent.id).desc()
        ).limit(limit).all()
        
        top_ids = [int(row.entity_id) for row in top]
        eng_map = self._engagement_by_post(top_ids, start_date)

        result: List[Dict[str, Any]] = []
        for row in top:
            post = self.db.query(Post).filter(Post.id == row.entity_id).first()
            if not post:
                continue
            e = eng_map.get(int(row.entity_id), {})
            likes = int(e.get("like", 0))
            comments = int(e.get("comment", 0))
            saves = int(e.get("save", 0))
            reposts = int(e.get("repost", 0))
            eng_sum = likes + comments + saves + reposts
            views_n = int(row.views)
            post_er = round(eng_sum / views_n * 100, 2) if views_n > 0 else 0.0
            result.append({
                "post_id": post.id,
                "title": post.title or "",
                "views": views_n,
                "likes": likes,
                "comments": comments,
                "saves": saves,
                "reposts": reposts,
                "engagement_rate": post_er,
            })

        return result


    def get_bot_analytics(
        self,
        *,
        bot_id: int,
        owner_user_id: int,
        days: int = 30,
    ) -> Dict[str, Any]:
        bot = (
            self.db.query(User)
            .filter(
                User.id == bot_id,
                User.is_bot.is_(True),
                User.created_by_user_id == owner_user_id,
            )
            .first()
        )
        if not bot:
            return {"error": "Bot not found or access denied"}
        start_date = datetime.utcnow() - timedelta(days=days)
        base = self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.entity_type == "bot",
            AnalyticsEvent.entity_id == bot_id,
            AnalyticsEvent.created_at >= start_date,
        )

        def _count(event_type: str) -> int:
            return int(
                base.filter(AnalyticsEvent.event_type == event_type)
                .count()
            )

        command_uses = _count("bot_command_invoked")
        callback_clicks = _count("bot_callback_click")
        unique_users = int(
            base.with_entities(func.count(func.distinct(AnalyticsEvent.user_id)))
            .scalar()
            or 0
        )
        ctr = (callback_clicks / command_uses * 100) if command_uses > 0 else 0.0

        by_day_rows = (
            self.db.query(
                func.date(AnalyticsEvent.created_at).label("date"),
                func.count(AnalyticsEvent.id).label("count"),
            )
            .filter(
                AnalyticsEvent.entity_type == "bot",
                AnalyticsEvent.entity_id == bot_id,
                AnalyticsEvent.event_type.in_(
                    ["bot_command_invoked", "bot_callback_click"]
                ),
                AnalyticsEvent.created_at >= start_date,
            )
            .group_by(func.date(AnalyticsEvent.created_at))
            .order_by(func.date(AnalyticsEvent.created_at))
            .all()
        )

        command_counts: Dict[str, int] = {}
        callback_counts: Dict[str, int] = {}
        for row in base.filter(
            AnalyticsEvent.event_type.in_(["bot_command_invoked", "bot_callback_click"])
        ).all():
            meta = row.event_metadata or {}
            if row.event_type == "bot_command_invoked":
                command = str(meta.get("command") or "").strip()
                if command:
                    command_counts[command] = command_counts.get(command, 0) + 1
            elif row.event_type == "bot_callback_click":
                data = str(meta.get("data") or "").strip()
                if data:
                    callback_counts[data] = callback_counts.get(data, 0) + 1
        top_commands = sorted(
            command_counts.items(),
            key=lambda item: item[1],
            reverse=True,
        )[:10]
        top_callbacks = sorted(
            callback_counts.items(),
            key=lambda item: item[1],
            reverse=True,
        )[:10]

        webhook_ok = _count("bot_webhook_delivery_ok")
        webhook_fail = _count("bot_webhook_delivery_fail")
        webhook_attempts = webhook_ok + webhook_fail
        webhook_success_rate = (
            (webhook_ok / webhook_attempts * 100) if webhook_attempts > 0 else 0.0
        )

        webhook_error_counts: Dict[str, int] = {}
        for row in base.filter(
            AnalyticsEvent.event_type == "bot_webhook_delivery_fail"
        ).all():
            meta = row.event_metadata or {}
            err = str(meta.get("error") or "").strip() or "unknown_error"
            webhook_error_counts[err] = webhook_error_counts.get(err, 0) + 1
        top_webhook_errors = sorted(
            webhook_error_counts.items(),
            key=lambda item: item[1],
            reverse=True,
        )[:5]

        return {
            "bot_id": bot_id,
            "period_days": days,
            "command_uses": command_uses,
            "callback_clicks": callback_clicks,
            "unique_users": unique_users,
            "callback_ctr_percent": round(ctr, 2),
            "by_day": [
                {
                    "date": row.date.isoformat() if row.date else None,
                    "count": int(row.count),
                }
                for row in by_day_rows
            ],
            "top_commands": [
                {"command": command, "count": int(count)}
                for command, count in top_commands
            ],
            "top_callbacks": [
                {"data": data, "count": int(count)}
                for data, count in top_callbacks
            ],
            "webhook_delivery": {
                "sent": int(webhook_ok),
                "failed": int(webhook_fail),
                "attempted": int(webhook_attempts),
                "success_rate_percent": round(webhook_success_rate, 2),
                "last_ok_at": bot.bot_webhook_last_ok_at.isoformat()
                if bot.bot_webhook_last_ok_at
                else None,
                "last_error": bot.bot_webhook_last_error,
                "top_errors": [
                    {"error": error_text, "count": int(count)}
                    for error_text, count in top_webhook_errors
                ],
            },
        }

    def get_bot_webhook_attempts(
        self,
        *,
        bot_id: int,
        owner_user_id: int,
        limit: int = 30,
    ) -> Dict[str, Any]:
        bot = (
            self.db.query(User)
            .filter(
                User.id == bot_id,
                User.is_bot.is_(True),
                User.created_by_user_id == owner_user_id,
            )
            .first()
        )
        if not bot:
            return {"error": "Bot not found or access denied"}

        max_limit = max(1, min(int(limit), 100))
        rows = (
            self.db.query(AnalyticsEvent)
            .filter(
                AnalyticsEvent.entity_type == "bot",
                AnalyticsEvent.entity_id == bot_id,
                AnalyticsEvent.event_type.in_(
                    [
                        "bot_webhook_delivery_ok",
                        "bot_webhook_delivery_fail",
                        "bot_webhook_auto_disabled",
                    ]
                ),
            )
            .order_by(AnalyticsEvent.created_at.desc(), AnalyticsEvent.id.desc())
            .limit(max_limit)
            .all()
        )

        attempts: List[Dict[str, Any]] = []
        for row in rows:
            meta = row.event_metadata or {}
            attempts.append(
                {
                    "id": int(row.id),
                    "event_type": row.event_type,
                    "status": (
                        "ok"
                        if row.event_type == "bot_webhook_delivery_ok"
                        else "auto_disabled"
                        if row.event_type == "bot_webhook_auto_disabled"
                        else "fail"
                    ),
                    "update_type": str(meta.get("update_type") or "").strip() or None,
                    "delivery_id": str(meta.get("delivery_id") or "").strip() or None,
                    "attempts_used": int(meta.get("attempts_used") or 0),
                    "error": str(meta.get("error") or meta.get("last_error") or "").strip()
                    or None,
                    "created_at": row.created_at.isoformat() if row.created_at else None,
                }
            )

        return {
            "bot_id": bot_id,
            "items": attempts,
        }

    def get_chat_channel_insights(self, *, user_id: int, days: int = 30) -> Dict[str, Any]:
        start_date = datetime.utcnow() - timedelta(days=days)
        sent_messages = int(
            self.db.query(func.count(Message.id))
            .filter(
                Message.sender_id == user_id,
                Message.deleted_at.is_(None),
                Message.created_at >= start_date,
            )
            .scalar()
            or 0
        )
        active_chats = int(
            self.db.query(func.count(func.distinct(Message.conversation_id)))
            .filter(
                Message.sender_id == user_id,
                Message.deleted_at.is_(None),
                Message.created_at >= start_date,
            )
            .scalar()
            or 0
        )
        channel_joins = int(
            self.db.query(func.count(ChannelMember.id))
            .filter(
                ChannelMember.user_id == user_id,
                ChannelMember.joined_at >= start_date,
            )
            .scalar()
            or 0
        )
        chat_events = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.event_type.like("chat_%"),
            AnalyticsEvent.created_at >= start_date,
        ).scalar() or 0
        channel_events = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.event_type.like("channel_%"),
            AnalyticsEvent.created_at >= start_date,
        ).scalar() or 0
        return {
            "period_days": days,
            "messages_sent": sent_messages,
            "active_chats": active_chats,
            "channel_joins": channel_joins,
            "chat_events": int(chat_events),
            "channel_events": int(channel_events),
        }

