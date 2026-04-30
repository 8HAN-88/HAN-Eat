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
    
    def get_profile_analytics(
        self,
        user_id: int,
        days: int = 30
    ) -> Dict[str, Any]:
        """Получить аналитику профиля"""
        start_date = datetime.utcnow() - timedelta(days=days)
        
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
                "total_views": 0,
                "total_engagement": {},
                "top_posts": [],
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
        
        # Топ постов по просмотрам
        top_posts = self._get_top_posts(post_ids, start_date, limit=10)
        
        # Статистика по дням
        daily_stats = self._get_daily_stats_for_posts(post_ids, start_date)
        
        return {
            "user_id": user_id,
            "period_days": days,
            "posts_count": len(post_ids),
            "total_views": total_views,
            "total_engagement": {
                "likes": total_likes,
                "comments": total_comments,
                "saves": total_saves,
                "reposts": total_reposts,
                "total": total_likes + total_comments + total_saves + total_reposts,
            },
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
        
        # Обогащаем данными о постах
        result = []
        for row in top:
            post = self.db.query(Post).filter(Post.id == row.entity_id).first()
            if post:
                result.append({
                    "post_id": post.id,
                    "title": post.title,
                    "views": row.views,
                })
        
        return result

