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

    def get_meal_plan_analytics(self, user_id: int, days: int = 30) -> Dict[str, Any]:
        """Продуктовая аналитика AI meal plan для пользователя."""
        start_date = datetime.utcnow() - timedelta(days=days)
        base = self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.event_type.like("meal_plan_%"),
            AnalyticsEvent.created_at >= start_date,
        )

        def _count(event_type: str) -> int:
            return (
                self.db.query(func.count(AnalyticsEvent.id))
                .filter(
                    AnalyticsEvent.user_id == user_id,
                    AnalyticsEvent.event_type == event_type,
                    AnalyticsEvent.created_at >= start_date,
                )
                .scalar()
                or 0
            )

        generations = _count("meal_plan_generated")
        regenerations = _count("meal_plan_regenerated")
        shopping = _count("meal_plan_shopping_applied")
        recipe_opens = _count("meal_plan_recipe_open")
        calendar_applies = _count("meal_plan_applied_to_calendar")

        durations: List[int] = []
        for row in base.filter(AnalyticsEvent.event_type == "meal_plan_generated").all():
            meta = row.event_metadata or {}
            d = meta.get("duration_days")
            if isinstance(d, int):
                durations.append(d)
            elif isinstance(d, (float, str)):
                try:
                    durations.append(int(d))
                except (TypeError, ValueError):
                    pass

        avg_duration = round(sum(durations) / len(durations), 1) if durations else 0

        return {
            "period_days": days,
            "plans_generated": generations,
            "regenerations": regenerations,
            "shopping_list_uses": shopping,
            "recipe_opens": recipe_opens,
            "calendar_applies": calendar_applies,
            "average_plan_duration_days": avg_duration,
            "retention_hint": generations > 0 and regenerations > 0,
        }

