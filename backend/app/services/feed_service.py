"""
Сервис для генерации и ранжирования ленты
"""
import math
import json
import pickle
import base64
import logging
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy import func, and_, or_, exists
from app.models.post import Post
from app.models.user import User

logger = logging.getLogger(__name__)


class FeedService:
    """
    Сервис для работы с лентой постов
    """

    @staticmethod
    def _recommendation_post_filters():
        """WARNING/shadow/ban: не показывать в ленте и рекомендациях."""
        blocked_author = exists().where(
            and_(
                User.id == Post.user_id,
                or_(User.shadow_moderation == True, User.banned_at.isnot(None)),
            )
        )
        return (
            Post.hidden_from_recommendations == False,
            ~blocked_author,
        )
    
    def __init__(self, db: Session, redis_client):
        self.db = db
        self.redis = redis_client
    
    def get_feed(
        self,
        user_id: int,
        cursor: Optional[str] = None,
        limit: int = 20,
        feed_type: str = "all",
        following_only: bool = False
    ) -> dict:
        """
        Получить персональную ленту пользователя
        
        Args:
            user_id: ID пользователя
            cursor: Курсор для пагинации
            limit: Количество постов
            feed_type: Тип ленты (all, reels, recipes, photos)
        """
        dismissed_ids = self._get_recent_dismissed_post_ids(user_id)

        from app.services.subscription_service import SubscriptionService
        from app.core.entitlements import subscription_entitlements

        tier, tier_active = SubscriptionService(self.db).effective_tier(user_id)
        hide_promoted = tier_active and subscription_entitlements(tier).get(
            "ad_free", False
        )

        # Проверяем кэш (только если нет курсора, т.к. курсор означает новую страницу)
        cache_key = (
            f"feed:{user_id}:{feed_type}:following_only={following_only}"
            f":hide_promo={hide_promoted}"
        )
        cached_data = None

        if not cursor:
            cached = self.redis.get(cache_key)
            if cached:
                try:
                    cached_data = self._deserialize_feed_cache(cached)
                    if cached_data:
                        cache_time = cached_data.get("cache_time")
                        if cache_time:
                            cache_age = (datetime.utcnow() - datetime.fromisoformat(cache_time)).total_seconds()
                            if cache_age < 300:  # 5 минут
                                feed_data = cached_data.get("feed", {})
                                items = feed_data.get("items", [])
                                # Не отдавать пустой кэш — всегда перезапрашивать, чтобы новые посты появились
                                if items:
                                    if dismissed_ids:
                                        feed_data = {
                                            **feed_data,
                                            "items": [
                                                it
                                                for it in items
                                                if it.get("id") not in dismissed_ids
                                            ],
                                        }
                                    logger.debug(f"Returning cached feed for user {user_id}, following_only={following_only}")
                                    return feed_data
                except Exception as e:
                    logger.warning(f"Failed to deserialize cached feed: {e}")

        # Получаем посты
        logger.debug(f"Fetching posts for user {user_id}, feed_type={feed_type}, following_only={following_only}")
        posts = self._fetch_posts(user_id, feed_type, following_only=following_only)
        logger.debug(f"Found {len(posts)} posts for user {user_id}, following_only={following_only}")

        # Ранжируем
        ranked_posts = self._rank_posts(posts, user_id)
        if dismissed_ids:
            ranked_posts = [p for p in ranked_posts if p.id not in dismissed_ids]

        if hide_promoted:
            ranked_posts = [
                p for p in ranked_posts if not getattr(p, "is_promoted", False)
            ]

        start_index = 0
        cursor_last_id = self._parse_feed_cursor(cursor)
        if cursor_last_id is not None:
            found = False
            for idx, p in enumerate(ranked_posts):
                if p.id == cursor_last_id:
                    start_index = idx + 1
                    found = True
                    break
            if not found:
                # Устаревший курсор (пост убран из выдачи / dismiss): не дублировать первую страницу.
                logger.debug(
                    "Feed cursor post_id=%s not in ranked list for user %s; returning empty page",
                    cursor_last_id,
                    user_id,
                )
                start_index = len(ranked_posts)

        window = ranked_posts[start_index : start_index + limit]
        enriched_posts = self._enrich_posts(window, user_id)

        has_more = len(ranked_posts) > start_index + limit
        # Курсор — последний отданный пост: клиент передаёт его id, мы начинаем со следующего индекса.
        last_in_window = window[-1] if window else None
        feed_result = {
            "items": enriched_posts,
            "next_cursor": self._generate_cursor(last_in_window) if has_more else None,
            "has_more": has_more,
        }
        
        # Кэшируем результат (только первую страницу и только непустой)
        if not cursor and feed_result.get("items"):
            try:
                cache_data = {
                    "feed": feed_result,
                    "cache_time": datetime.utcnow().isoformat()
                }
                serialized = self._serialize_feed_cache(cache_data)
                if serialized:
                    self.redis.setex(cache_key, 300, serialized)  # Кэш на 5 минут
            except Exception as e:
                logger.warning(f"Failed to cache feed: {e}")
        
        return feed_result
    
    def _fetch_posts(self, user_id: int, feed_type: str, following_only: bool = False) -> List[Post]:
        """Получить посты для ленты (включая репосты и посты из каналов)"""
        from app.models.follower import Follower
        from app.models.repost import Repost
        from app.models.community_member import ChannelMember
        from app.models.community import Channel
        
        # Получаем подписки пользователя
        following = self.db.query(Follower.followee_id).filter(
            Follower.follower_id == user_id
        ).all()
        following_ids = [row[0] for row in following]
        
        # Получаем каналы, на которые подписан пользователь
        channel_memberships = self.db.query(ChannelMember.channel_id, ChannelMember.role).filter(
            ChannelMember.user_id == user_id
        ).all()
        subscribed_channel_ids = [row[0] for row in channel_memberships]
        subscribed_channels_with_roles = {row[0]: row[1] for row in channel_memberships}
        
        # Также включаем каналы, где пользователь является владельцем (admin_user_id)
        owned_channels = self.db.query(Channel.id).filter(
            Channel.admin_user_id == user_id
        ).all()
        owned_channel_ids = [row[0] for row in owned_channels]
        
        # Объединяем подписанные и собственные каналы
        all_user_channel_ids = list(set(subscribed_channel_ids + owned_channel_ids))
        
        logger.debug(f"User {user_id}: following_ids={following_ids}, subscribed_channel_ids={subscribed_channel_ids}, owned_channel_ids={owned_channel_ids}, all_user_channel_ids={all_user_channel_ids}")
        
        # Если требуется только подписки
        if following_only:
            # Если нет подписок и нет каналов, возвращаем пустой список
            if not following_ids and not all_user_channel_ids:
                logger.info(f"User {user_id}: No following and no channels, returning empty list")
                return []
            
            # Получаем ID постов, которые репостнули подписки
            reposted_posts = self.db.query(Repost.post_id).filter(
                Repost.user_id.in_(following_ids)
            ).distinct().all()
            reposted_post_ids = [row[0] for row in reposted_posts]
            
            # Запрос постов от подписок (оригинальные) и из каналов
            # Для постов из каналов не применяем фильтр по visibility, т.к. они всегда доступны участникам
            conditions = []
            if following_ids:
                conditions.append(and_(
                    Post.user_id.in_(following_ids),
                    Post.visibility.in_(["public", "followers"])
                ))
            if all_user_channel_ids:
                # Посты из каналов (подписанных и собственных) - без фильтра по visibility для участников
                conditions.append(and_(
                    Post.channel_id.in_(all_user_channel_ids),
                    Post.channel_id.isnot(None)
                ))
            if not conditions:
                logger.debug(f"User {user_id} (following_only=True): No conditions, returning empty list")
                return []
            
            # Оптимизация: используем eager loading для избежания N+1 запросов
            query = self.db.query(Post).options(
                joinedload(Post.user),  # Загружаем автора сразу
                selectinload(Post.channel)  # Загружаем канал если есть
            ).filter(
                or_(*conditions),
                Post.status == "published",
                Post.deleted_at.is_(None),
                *FeedService._recommendation_post_filters(),
            )
            
            if feed_type != "all":
                query = query.filter(Post.type == feed_type)
            
            original_posts = query.order_by(Post.published_at.desc()).limit(100).all()
            logger.debug(f"User {user_id} (following_only=True): Found {len(original_posts)} posts")
            
            # Добавляем репостнутые посты (если они еще не включены)
            if reposted_post_ids:
                # Оптимизация: eager loading для репостнутых постов
                reposted_query = self.db.query(Post).options(
                    joinedload(Post.user),
                    selectinload(Post.channel)
                ).filter(
                    Post.id.in_(reposted_post_ids),
                    Post.status == "published",
                    Post.visibility.in_(["public", "followers"]),
                    Post.deleted_at.is_(None),
                    *FeedService._recommendation_post_filters(),
                )
                
                if feed_type != "all":
                    reposted_query = reposted_query.filter(Post.type == feed_type)
                
                reposted_posts_list = reposted_query.order_by(Post.published_at.desc()).limit(50).all()
                
                # Объединяем, избегая дубликатов
                original_ids = {p.id for p in original_posts}
                for p in reposted_posts_list:
                    if p.id not in original_ids:
                        original_posts.append(p)
            
            return original_posts[:100]  # Ограничиваем общее количество
        
        # Если following_only=False, показываем рекомендации
        # Но также включаем посты из каналов, где пользователь является участником или владельцем
        # (чтобы владелец/участник мог видеть свои посты из канала)
        
        logger.debug(f"User {user_id} (following_only=False): owned_channel_ids={owned_channel_ids}, all_user_channel_ids={all_user_channel_ids}")
        
        # Получаем ID постов, которые репостнули подписки
        reposted_posts = self.db.query(Repost.post_id).filter(
            Repost.user_id.in_(following_ids)
        ).distinct().all()
        reposted_post_ids = [row[0] for row in reposted_posts]
        
        # Запрос постов для рекомендаций:
        # 1. Посты от подписок (публичные или для подписчиков)
        # 2. Посты из каналов, где пользователь является участником или владельцем
        # 3. Все публичные посты (не из каналов)
        conditions = []
        if following_ids:
            conditions.append(and_(
                Post.user_id.in_(following_ids),
                Post.visibility.in_(["public", "followers"])
            ))
        # Посты из каналов, где пользователь является участником или владельцем
        if all_user_channel_ids:
            conditions.append(and_(
                Post.channel_id.in_(all_user_channel_ids),
                Post.channel_id.isnot(None)
            ))
        # Все публичные посты (не из каналов)
        conditions.append(and_(
            Post.visibility == "public",
            Post.channel_id.is_(None)  # Посты не из каналов
        ))
        
        # Оптимизация: используем eager loading для избежания N+1 запросов
        query = self.db.query(Post).options(
            joinedload(Post.user),  # Загружаем автора сразу
            selectinload(Post.channel)  # Загружаем канал если есть
        ).filter(
            or_(*conditions),
            Post.status == "published",
            Post.deleted_at.is_(None),
            *FeedService._recommendation_post_filters(),
        )
        
        if feed_type != "all":
            query = query.filter(Post.type == feed_type)
        
        original_posts = query.order_by(Post.published_at.desc()).limit(100).all()
        logger.debug(f"User {user_id} (following_only=False): Found {len(original_posts)} posts")
        
        # Добавляем репостнутые посты (если они еще не включены)
        if reposted_post_ids:
            # Оптимизация: eager loading для репостнутых постов
            reposted_query = self.db.query(Post).options(
                joinedload(Post.user),
                selectinload(Post.channel)
            ).filter(
                Post.id.in_(reposted_post_ids),
                Post.status == "published",
                Post.visibility.in_(["public", "followers"]),
                Post.deleted_at.is_(None),
                *FeedService._recommendation_post_filters(),
            )
            
            if feed_type != "all":
                reposted_query = reposted_query.filter(Post.type == feed_type)
            
            reposted_posts_list = reposted_query.order_by(Post.published_at.desc()).limit(50).all()
            
            # Объединяем, избегая дубликатов
            original_ids = {p.id for p in original_posts}
            for p in reposted_posts_list:
                if p.id not in original_ids:
                    original_posts.append(p)
        
        return original_posts[:100]  # Ограничиваем общее количество
    
    def _rank_posts(self, posts: List[Post], user_id: int) -> List[Post]:
        """
        Ранжирование постов по релевантности с персонализацией
        
        Phase 0: Rule-based ranking с учетом истории просмотров
        """
        now = datetime.utcnow()
        user = self._get_user(user_id)
        
        # Получаем паттерны просмотров для персонализации
        viewing_patterns = self._get_user_viewing_patterns(user_id)
        
        scored_posts = []
        for post in posts:
            # Базовый score
            score = self._calculate_score(post, user, now)
            
            # Персонализация на основе истории просмотров
            personalization_boost = self._calculate_personalization_boost(
                user_id, post, viewing_patterns
            )
            score *= personalization_boost
            
            scored_posts.append((score, post))
        
        # Сортируем по score (убывание)
        scored_posts.sort(key=lambda x: x[0], reverse=True)
        
        return [post for _, post in scored_posts]
    
    def _calculate_personalization_boost(
        self,
        user_id: int,
        post: Post,
        viewing_patterns: Dict[str, Any]
    ) -> float:
        """Вычислить boost персонализации на основе истории просмотров"""
        boost = 1.0
        
        # 1. Учитываем предпочтения по авторам
        author_interaction_score = self._get_author_interaction_score(user_id, post.user_id)
        if author_interaction_score > 0.5:
            boost *= (1.0 + author_interaction_score * 0.2)  # До 20% boost
        
        # 2. Учитываем предпочтения по типам постов
        preferred_types = self._get_user_preferred_post_types(user_id)
        if post.type in preferred_types:
            type_preference = preferred_types[post.type]
            boost *= (1.0 + type_preference * 0.15)  # До 15% boost
        
        # 3. Штраф за часто пропускаемые авторы
        if self._is_author_frequently_skipped(user_id, post.user_id):
            boost *= 0.7  # 30% штраф
        
        # 4. Буст для новых авторов (которых пользователь еще не видел)
        if not self._has_user_viewed_author_posts(user_id, post.user_id):
            boost *= 1.1  # 10% boost для новых авторов
        
        return boost
    
    def _get_author_interaction_score(self, user_id: int, author_id: int) -> float:
        """Вычислить score взаимодействия с автором"""
        from app.models.like import Like
        from app.models.saved_post import SavedPost
        from app.models.comment import Comment
        from app.models.analytics_event import AnalyticsEvent
        from datetime import datetime, timedelta
        
        recent_date = datetime.utcnow() - timedelta(days=30)
        
        # Лайки постов автора
        likes_count = self.db.query(func.count(Like.id)).join(Post, Like.post_id == Post.id).filter(
            Like.user_id == user_id,
            Post.user_id == author_id,
            Post.published_at >= recent_date
        ).scalar() or 0
        
        # Сохранения постов автора
        saves_count = self.db.query(func.count(SavedPost.id)).join(Post, SavedPost.post_id == Post.id).filter(
            SavedPost.user_id == user_id,
            Post.user_id == author_id,
            Post.published_at >= recent_date
        ).scalar() or 0
        
        # Комментарии к постам автора
        comments_count = self.db.query(func.count(Comment.id)).join(Post, Comment.post_id == Post.id).filter(
            Comment.user_id == user_id,
            Post.user_id == author_id,
            Post.published_at >= recent_date
        ).scalar() or 0
        
        # Просмотры постов автора (только хорошие просмотры)
        good_views_count = 0
        for view_event in self.db.query(AnalyticsEvent).join(Post, and_(AnalyticsEvent.entity_id == Post.id, AnalyticsEvent.entity_type == "post")).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.event_type == "view",
            Post.user_id == author_id,
            AnalyticsEvent.created_at >= recent_date
        ).limit(50).all():
            duration = view_event.event_metadata.get("duration_seconds") if view_event.event_metadata else 0
            if duration and duration >= 3.0:
                good_views_count += 1
        
        # Взвешенная сумма взаимодействий
        interaction_score = (
            likes_count * 3.0 +
            saves_count * 2.5 +
            comments_count * 4.0 +
            good_views_count * 1.0
        )
        
        # Нормализуем (10+ взаимодействий = 1.0)
        normalized_score = min(interaction_score / 10.0, 1.0)
        
        return normalized_score
    
    def _is_author_frequently_skipped(self, user_id: int, author_id: int) -> bool:
        """Проверить, часто ли пользователь пропускает посты этого автора"""
        from app.models.analytics_event import AnalyticsEvent
        from datetime import datetime, timedelta
        
        recent_date = datetime.utcnow() - timedelta(days=30)
        
        # Получаем все просмотры постов автора
        views = self.db.query(AnalyticsEvent).join(Post, and_(AnalyticsEvent.entity_id == Post.id, AnalyticsEvent.entity_type == "post")).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.event_type == "view",
            Post.user_id == author_id,
            AnalyticsEvent.created_at >= recent_date
        ).limit(20).all()
        
        if len(views) < 3:  # Недостаточно данных
            return False
        
        # Считаем пропуски
        skipped = 0
        for view in views:
            duration = view.event_metadata.get("duration_seconds") if view.event_metadata else 0
            if duration and duration < 0.5:
                skipped += 1
        
        # Если больше 50% просмотров были пропусками
        skip_rate = skipped / len(views)
        return skip_rate > 0.5
    
    def _has_user_viewed_author_posts(self, user_id: int, author_id: int) -> bool:
        """Проверить, просматривал ли пользователь посты этого автора"""
        from app.models.analytics_event import AnalyticsEvent
        
        return self.db.query(AnalyticsEvent).join(Post, and_(AnalyticsEvent.entity_id == Post.id, AnalyticsEvent.entity_type == "post")).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.event_type == "view",
            Post.user_id == author_id
        ).first() is not None
    
    def _calculate_score(
        self,
        post: Post,
        user: User,
        now: datetime
    ) -> float:
        """
        Вычислить score поста для пользователя
        
        Формула:
        score = w1 * user_similarity + w2 * recency + w3 * engagement + w4 * author_score
        """
        # 1. User similarity (0-1)
        similarity = self._calculate_user_similarity(post, user)
        
        # 2. Recency (0-1) - экспоненциальное затухание
        if post.published_at:
            hours_ago = (now - post.published_at).total_seconds() / 3600
            recency = math.exp(-hours_ago / 24)  # half-life 24 часа
        else:
            recency = 0.5  # если нет даты публикации
        
        # 3. Engagement (0-1)
        engagement = self._calculate_engagement(post)
        
        # 4. Author score (0-1)
        author_score = self._calculate_author_score(post.user_id)
        
        # 5. Business boost
        boost = 1.0
        
        # Приоритет для Plus подписчиков (если автор Plus)
        from app.services.subscription_service import SubscriptionService
        subscription_service = SubscriptionService(self.db)
        if subscription_service.is_user_plus(post.user_id):
            boost *= 1.3  # 30% boost для постов от Plus авторов

        if getattr(post, "is_promoted", False):
            boost *= 1.25

        if post.channel_id:
            # Проверяем, является ли пользователь участником канала
            is_member = self._is_channel_member(user.id, post.channel_id)
            if is_member:
                boost *= 1.2
        
        # 6. Дополнительные сигналы
        additional_signals = 1.0
        
        # Буст для постов, которые пользователь еще не видел
        has_viewed = self._has_user_viewed_post(user.id, post.id)
        if not has_viewed:
            additional_signals *= 1.1  # 10% boost для новых постов
        else:
            # Если пользователь уже видел пост, учитываем вовлеченность
            view_engagement = self._calculate_view_engagement(user.id, post.id)
            if view_engagement > 0.7:  # Хороший просмотр
                # Не показываем повторно хорошо просмотренные посты
                additional_signals *= 0.3  # Сильно снижаем score
            elif view_engagement > 0.3:  # Средний просмотр
                additional_signals *= 0.7  # Умеренно снижаем
        
        # Штраф: явное «скрыть из ленты» сильнее, чем быстрый скролл
        if self._has_user_dismissed_post(user.id, post.id):
            additional_signals *= 0.2
        elif self._has_user_skipped_post(user.id, post.id):
            additional_signals *= 0.5  # 50% штраф за пропущенные посты

        # Буст для постов от подписок (если это подписка)
        is_following_author = self._is_following(user.id, post.user_id)
        if is_following_author:
            additional_signals *= 1.15  # 15% boost для постов от подписок
        
        # Буст для репостов от подписок
        if self._is_repost_from_following(user.id, post.id):
            additional_signals *= 1.1
        
        # Временной boost (на основе паттернов активности)
        time_boost = self._calculate_time_based_boost(user.id, post)
        additional_signals *= time_boost
        
        # Final score
        score = (
            0.3 * similarity +
            0.2 * recency +
            0.3 * engagement +
            0.15 * author_score +
            0.05 * additional_signals  # Небольшой вес для дополнительных сигналов
        ) * boost * additional_signals
        
        return score
    
    def _has_user_viewed_post(self, user_id: int, post_id: int) -> bool:
        """Проверить, просматривал ли пользователь этот пост"""
        from app.models.analytics_event import AnalyticsEvent
        return self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "view"
        ).first() is not None
    
    def _get_view_duration(self, user_id: int, post_id: int) -> Optional[float]:
        """Получить время просмотра поста в секундах (из metadata)"""
        from app.models.analytics_event import AnalyticsEvent
        event = self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post_id,
            AnalyticsEvent.event_type == "view"
        ).order_by(AnalyticsEvent.created_at.desc()).first()
        
        if event and event.event_metadata:
            return event.event_metadata.get("duration_seconds")
        return None
    
    def _calculate_view_engagement(self, user_id: int, post_id: int) -> float:
        """Вычислить вовлеченность на основе времени просмотра"""
        duration = self._get_view_duration(user_id, post_id)
        if duration is None:
            return 0.0
        
        # Нормализуем время просмотра
        # Для фото/текста: 3+ секунды = хороший просмотр
        # Для видео: 50%+ просмотра = хороший просмотр
        post = self.db.query(Post).filter(Post.id == post_id).first()
        if not post:
            return 0.0
        
        if post.type in ["photo", "text", "recipe"]:
            # Для статичного контента: 3+ секунды = 1.0
            engagement = min(duration / 3.0, 1.0)
        elif post.type == "reel":
            # Для видео: учитываем процент просмотра
            video_duration = post.body.get("duration_seconds") if post.body else 30  # по умолчанию 30 сек
            if video_duration:
                view_percentage = duration / video_duration
                engagement = min(view_percentage * 1.5, 1.0)  # 66%+ просмотра = 1.0
            else:
                engagement = min(duration / 20.0, 1.0)  # 20+ секунд = 1.0
        else:
            engagement = min(duration / 5.0, 1.0)  # по умолчанию
        
        return engagement
    
    def _has_user_skipped_post(self, user_id: int, post_id: int) -> bool:
        """Проверить, пропустил ли пользователь этот пост (быстрый скролл)"""
        duration = self._get_view_duration(user_id, post_id)
        if duration is None:
            return False
        
        # Если просмотр был меньше 0.5 секунды, считаем пропуском
        return duration < 0.5

    def _has_user_dismissed_post(self, user_id: int, post_id: int) -> bool:
        """Пользователь явно скрыл пост (POST /feed/dismiss)."""
        from app.models.analytics_event import AnalyticsEvent

        return (
            self.db.query(AnalyticsEvent)
            .filter(
                AnalyticsEvent.user_id == user_id,
                AnalyticsEvent.entity_type == "post",
                AnalyticsEvent.entity_id == post_id,
                AnalyticsEvent.event_type == "dismiss",
            )
            .first()
            is not None
        )

    def _get_recent_dismissed_post_ids(self, user_id: int, days: int = 14) -> set:
        """Посты, которые пользователь явно скрыл из ленты за последние `days` дней."""
        from app.models.analytics_event import AnalyticsEvent

        cutoff = datetime.utcnow() - timedelta(days=days)
        rows = (
            self.db.query(AnalyticsEvent.entity_id)
            .filter(
                AnalyticsEvent.user_id == user_id,
                AnalyticsEvent.event_type == "dismiss",
                AnalyticsEvent.entity_type == "post",
                AnalyticsEvent.created_at >= cutoff,
            )
            .distinct()
            .all()
        )
        return {int(r[0]) for r in rows if r[0] is not None}

    def _get_user_viewing_patterns(self, user_id: int) -> Dict[str, Any]:
        """Получить паттерны просмотров пользователя"""
        from app.models.analytics_event import AnalyticsEvent
        from datetime import datetime, timedelta
        
        recent_date = datetime.utcnow() - timedelta(days=30)
        
        # Получаем все просмотры за последние 30 дней
        views = self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.created_at >= recent_date
        ).all()
        
        if not views:
            return {
                "avg_view_duration": 0.0,
                "preferred_hours": [],
                "total_views": 0,
                "skipped_posts": 0
            }
        
        # Анализируем время просмотра
        durations = []
        skipped = 0
        hour_counts = {}
        
        for view in views:
            duration = view.event_metadata.get("duration_seconds") if view.event_metadata else None
            if duration:
                if duration < 0.5:
                    skipped += 1
                else:
                    durations.append(duration)
            
            # Считаем активность по часам
            hour = view.created_at.hour
            hour_counts[hour] = hour_counts.get(hour, 0) + 1
        
        # Находим предпочтительные часы (топ-3)
        preferred_hours = sorted(hour_counts.items(), key=lambda x: x[1], reverse=True)[:3]
        preferred_hours = [h for h, _ in preferred_hours]
        
        avg_duration = sum(durations) / len(durations) if durations else 0.0
        
        return {
            "avg_view_duration": avg_duration,
            "preferred_hours": preferred_hours,
            "total_views": len(views),
            "skipped_posts": skipped
        }
    
    def _calculate_time_based_boost(self, user_id: int, post: Post) -> float:
        """Вычислить boost на основе времени суток и активности пользователя"""
        patterns = self._get_user_viewing_patterns(user_id)
        preferred_hours = patterns.get("preferred_hours", [])
        
        if not preferred_hours:
            return 1.0
        
        # Получаем текущий час
        current_hour = datetime.utcnow().hour
        
        # Если текущий час в предпочтительных, даем небольшой boost
        if current_hour in preferred_hours:
            return 1.1  # 10% boost
        
        # Проверяем близость к предпочтительным часам (±1 час)
        for preferred_hour in preferred_hours:
            if abs(current_hour - preferred_hour) <= 1:
                return 1.05  # 5% boost
        
        return 1.0
    
    def _is_following(self, follower_id: int, followee_id: int) -> bool:
        """Проверить, подписан ли пользователь на автора"""
        from app.models.follower import Follower
        return self.db.query(Follower).filter(
            Follower.follower_id == follower_id,
            Follower.followee_id == followee_id
        ).first() is not None
    
    def _is_repost_from_following(self, user_id: int, post_id: int) -> bool:
        """Проверить, репостнул ли пост кто-то из подписок пользователя"""
        from app.models.follower import Follower
        from app.models.repost import Repost
        
        # Получаем подписки пользователя
        following = self.db.query(Follower.followee_id).filter(
            Follower.follower_id == user_id
        ).all()
        following_ids = [row[0] for row in following]
        
        if not following_ids:
            return False
        
        # Проверяем, репостнул ли кто-то из подписок этот пост
        return self.db.query(Repost).filter(
            Repost.user_id.in_(following_ids),
            Repost.post_id == post_id
        ).first() is not None
    
    def _calculate_user_similarity(self, post: Post, user: User) -> float:
        """Вычислить схожесть интересов пользователя с постом"""
        from app.models.follower import Follower
        from app.models.like import Like
        from app.models.saved_post import SavedPost
        
        similarity_score = 0.0
        weights_sum = 0.0
        
        # 1. Теги (вес 0.4) - улучшенная версия с весами
        user_interests = self._get_user_interests(user.id)
        post_tags = set(post.tags or [])
        
        if post_tags and user_interests:
            # Вычисляем взвешенную схожесть
            total_weight = 0.0
            matched_weight = 0.0
            
            for tag in post_tags:
                tag_weight = user_interests.get(tag, 0)
                total_weight += 1.0  # Каждый тег поста имеет базовый вес 1.0
                if tag_weight > 0:
                    # Учитываем вес интереса пользователя к этому тегу
                    matched_weight += min(tag_weight / 5.0, 1.0)  # Нормализуем до 1.0
            
            if total_weight > 0:
                tag_similarity = matched_weight / total_weight
            else:
                tag_similarity = 0.0
            
            similarity_score += tag_similarity * 0.4
            weights_sum += 0.4
        else:
            weights_sum += 0.4  # Нейтральный score для тегов
        
        # 2. Подписка на автора (вес 0.3)
        is_following = self.db.query(Follower).filter(
            Follower.follower_id == user.id,
            Follower.followee_id == post.user_id
        ).first() is not None
        
        if is_following:
            similarity_score += 1.0 * 0.3
        weights_sum += 0.3
        
        # 3. История взаимодействий с автором (вес 0.2)
        # Проверяем, лайкал ли пользователь посты этого автора
        liked_author_posts = self.db.query(func.count(Like.id)).join(Post, Like.post_id == Post.id).filter(
            Like.user_id == user.id,
            Post.user_id == post.user_id,
            Post.id != post.id  # Исключаем текущий пост
        ).scalar() or 0
        
        author_interaction = min(liked_author_posts / 5.0, 1.0)  # 5+ лайков = 1.0
        similarity_score += author_interaction * 0.2
        weights_sum += 0.2
        
        # 4. Тип поста (вес 0.1)
        # Проверяем, какие типы постов пользователь предпочитает
        user_preferred_types = self._get_user_preferred_post_types(user.id)
        if post.type in user_preferred_types:
            type_similarity = user_preferred_types[post.type]
            similarity_score += type_similarity * 0.1
        weights_sum += 0.1
        
        # Нормализуем по сумме весов
        if weights_sum > 0:
            similarity = similarity_score / weights_sum
        else:
            similarity = 0.5  # Нейтральный score
        
        return min(similarity, 1.0)
    
    def _get_user_preferred_post_types(self, user_id: int) -> Dict[str, float]:
        """Получить предпочтения пользователя по типам постов"""
        from app.models.like import Like
        from app.models.saved_post import SavedPost
        from sqlalchemy import func
        from datetime import datetime, timedelta
        
        recent_date = datetime.utcnow() - timedelta(days=90)
        
        # Считаем лайки по типам
        liked_by_type = {}
        liked_posts = self.db.query(Post.type, func.count(Like.id)).join(Like, Post.id == Like.post_id).filter(
            Like.user_id == user_id,
            Post.published_at >= recent_date
        ).group_by(Post.type).all()
        
        total_likes = sum(count for _, count in liked_posts)
        
        for post_type, count in liked_posts:
            if total_likes > 0:
                liked_by_type[post_type] = count / total_likes
        
        # Считаем сохранения по типам
        saved_by_type = {}
        saved_posts = self.db.query(Post.type, func.count(SavedPost.id)).join(SavedPost, Post.id == SavedPost.post_id).filter(
            SavedPost.user_id == user_id,
            Post.published_at >= recent_date
        ).group_by(Post.type).all()
        
        total_saves = sum(count for _, count in saved_posts)
        
        for post_type, count in saved_posts:
            if total_saves > 0:
                saved_by_type[post_type] = count / total_saves
        
        # Объединяем (лайки важнее сохранений)
        preferences = {}
        all_types = set(liked_by_type.keys()) | set(saved_by_type.keys())
        
        for post_type in all_types:
            like_score = liked_by_type.get(post_type, 0) * 0.7
            save_score = saved_by_type.get(post_type, 0) * 0.3
            preferences[post_type] = like_score + save_score
        
        return preferences
    
    def _calculate_engagement(self, post: Post) -> float:
        """Вычислить вовлеченность поста"""
        from app.models.like import Like
        from app.models.comment import Comment
        from app.models.saved_post import SavedPost
        from app.models.repost import Repost
        from app.models.analytics_event import AnalyticsEvent
        from sqlalchemy import func
        from datetime import datetime, timedelta
        
        # Получаем метрики из БД (за последние 7 дней для актуальности)
        recent_date = datetime.utcnow() - timedelta(days=7)
        
        # Количество лайков
        likes_count = self.db.query(func.count(Like.id)).filter(
            Like.post_id == post.id
        ).scalar() or 0
        
        # Количество комментариев
        comments_count = self.db.query(func.count(Comment.id)).filter(
            Comment.post_id == post.id,
            Comment.deleted_at.is_(None)
        ).scalar() or 0
        
        # Количество сохранений
        saves_count = self.db.query(func.count(SavedPost.id)).filter(
            SavedPost.post_id == post.id
        ).scalar() or 0
        
        # Количество репостов
        reposts_count = self.db.query(func.count(Repost.id)).filter(
            Repost.post_id == post.id
        ).scalar() or 0
        
        # Количество просмотров (из analytics)
        views_count = self.db.query(func.count(AnalyticsEvent.id)).filter(
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.entity_id == post.id,
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= recent_date
        ).scalar() or 1  # Минимум 1, чтобы избежать деления на 0
        
        # Вычисляем rates
        like_rate = likes_count / max(views_count, 1)
        comment_rate = comments_count / max(views_count, 1)
        save_rate = saves_count / max(views_count, 1)
        repost_rate = reposts_count / max(views_count, 1)
        
        # Нормализуем rates (используем логарифмическую шкалу для больших значений)
        import math
        like_score = min(math.log1p(like_rate * 100) / 5, 1.0)  # log1p для плавного роста
        comment_score = min(math.log1p(comment_rate * 100) / 4, 1.0)
        save_score = min(math.log1p(save_rate * 100) / 3, 1.0)
        repost_score = min(math.log1p(repost_rate * 100) / 2, 1.0)
        
        # Взвешенная сумма
        engagement = (
            like_score * 0.4 +
            comment_score * 0.3 +
            save_score * 0.2 +
            repost_score * 0.1
        )
        
        return min(engagement, 1.0)
    
    def _calculate_author_score(self, author_id: int) -> float:
        """Вычислить score автора на основе его метрик"""
        from app.models.follower import Follower
        from app.models.analytics_event import AnalyticsEvent
        from sqlalchemy import func
        from datetime import datetime, timedelta
        
        # 1. Количество подписчиков (нормализованное)
        followers_count = self.db.query(func.count(Follower.id)).filter(
            Follower.followee_id == author_id
        ).scalar() or 0
        
        # Логарифмическая нормализация для подписчиков
        import math
        followers_score = min(math.log1p(followers_count) / 8, 1.0)  # ~3000 подписчиков = 1.0
        
        # 2. Средняя вовлеченность постов автора (за последние 30 дней)
        recent_date = datetime.utcnow() - timedelta(days=30)
        
        author_posts = self.db.query(Post).filter(
            Post.user_id == author_id,
            Post.status == "published",
            Post.published_at >= recent_date,
            Post.deleted_at.is_(None)
        ).limit(50).all()
        
        if not author_posts:
            return 0.5  # Нейтральный score для новых авторов
        
        # Вычисляем среднюю вовлеченность
        total_engagement = 0.0
        for post in author_posts:
            total_engagement += self._calculate_engagement(post)
        
        avg_engagement = total_engagement / len(author_posts)
        
        # 3. Скорость роста (новые подписчики за последние 7 дней)
        week_ago = datetime.utcnow() - timedelta(days=7)
        recent_followers = self.db.query(func.count(Follower.id)).filter(
            Follower.followee_id == author_id,
            Follower.created_at >= week_ago
        ).scalar() or 0
        
        growth_score = min(recent_followers / 10.0, 1.0)  # 10+ новых подписчиков = 1.0
        
        # 4. Проверка на верификацию
        author = self.db.query(User).filter(User.id == author_id).first()
        verified_boost = 1.1 if author and author.is_verified else 1.0
        
        # Итоговый score
        author_score = (
            followers_score * 0.3 +
            avg_engagement * 0.5 +
            growth_score * 0.2
        ) * verified_boost
        
        return min(author_score, 1.0)
    
    def _get_user_interests(self, user_id: int) -> Dict[str, float]:
        """Получить интересы пользователя с весами (теги из лайков, сохранений, просмотров)"""
        from app.models.like import Like
        from app.models.saved_post import SavedPost
        from app.models.analytics_event import AnalyticsEvent
        from datetime import datetime, timedelta
        from sqlalchemy import and_
        
        interests = {}  # {tag: weight}
        
        # Получаем теги из постов, которые пользователь лайкнул (за последние 90 дней)
        recent_date = datetime.utcnow() - timedelta(days=90)
        
        liked_posts = self.db.query(Post).join(Like, Post.id == Like.post_id).filter(
            Like.user_id == user_id,
            Post.published_at >= recent_date
        ).limit(100).all()
        
        for post in liked_posts:
            if post.tags:
                for tag in post.tags:
                    interests[tag] = interests.get(tag, 0) + 3.0  # Лайки имеют вес 3.0
        
        # Получаем теги из сохраненных постов
        saved_posts = self.db.query(Post).join(SavedPost, Post.id == SavedPost.post_id).filter(
            SavedPost.user_id == user_id,
            Post.published_at >= recent_date
        ).limit(100).all()
        
        for post in saved_posts:
            if post.tags:
                for tag in post.tags:
                    interests[tag] = interests.get(tag, 0) + 2.5  # Сохранения имеют вес 2.5
        
        # Получаем теги из постов с хорошим просмотром (engagement)
        viewed_events = self.db.query(AnalyticsEvent).filter(
            AnalyticsEvent.user_id == user_id,
            AnalyticsEvent.entity_type == "post",
            AnalyticsEvent.event_type == "view",
            AnalyticsEvent.created_at >= recent_date
        ).limit(200).all()
        
        for event in viewed_events:
            duration = event.event_metadata.get("duration_seconds") if event.event_metadata else 0
            if duration and duration >= 3.0:  # Только хорошие просмотры (3+ секунды)
                post = self.db.query(Post).filter(Post.id == event.entity_id).first()
                if post and post.tags:
                    # Вес зависит от времени просмотра
                    view_weight = min(duration / 10.0, 2.0)  # Максимум 2.0 для просмотров
                    for tag in post.tags:
                        interests[tag] = interests.get(tag, 0) + view_weight
        
        return interests
    
    def _get_user_interests_set(self, user_id: int) -> set:
        """Получить интересы пользователя как set (для обратной совместимости)"""
        interests_dict = self._get_user_interests(user_id)
        # Возвращаем только теги с весом > 1.0
        return {tag for tag, weight in interests_dict.items() if weight > 1.0}
    
    def _get_recommended_posts(
        self,
        user_id: int,
        feed_type: str,
        limit: int = 20
    ) -> List[Post]:
        """Получить рекомендованные посты (если нет подписок)"""
        from app.models.community import Channel
        
        # Получаем публичные каналы
        public_channels = self.db.query(Channel.id).filter(
            Channel.is_public == True
        ).all()
        public_channel_ids = [row[0] for row in public_channels]
        
        # Включаем публичные посты и посты из публичных каналов
        conditions = [
            and_(
                Post.visibility == "public",
                Post.channel_id.is_(None)  # Посты не из каналов
            )
        ]
        
        if public_channel_ids:
            conditions.append(Post.channel_id.in_(public_channel_ids))
        
        query = self.db.query(Post).filter(
            or_(*conditions),
            Post.status == "published",
            Post.deleted_at.is_(None),
            *FeedService._recommendation_post_filters(),
        )
        
        if feed_type != "all":
            query = query.filter(Post.type == feed_type)
        
        posts = query.order_by(Post.published_at.desc()).limit(limit).all()
        return posts
    
    def _parse_feed_cursor(self, cursor: Optional[str]) -> Optional[int]:
        """
        Декодирует курсор: base64 JSON {id, published_at} от _generate_cursor,
        либо сырой числовой id (совместимость со старыми клиентами).
        """
        if not cursor or not str(cursor).strip():
            return None
        raw = str(cursor).strip()
        try:
            import base64
            import json

            data = json.loads(base64.b64decode(raw.encode()).decode())
            if isinstance(data, dict) and data.get("id") is not None:
                return int(data["id"])
        except Exception:
            pass
        try:
            return int(raw)
        except Exception:
            return None

    def _generate_cursor(self, post: Optional[Post]) -> Optional[str]:
        """Генерация курсора для пагинации"""
        if not post:
            return None
        import base64
        import json
        published_at = post.published_at.isoformat() if post.published_at else ""
        cursor_data = {"id": post.id, "published_at": published_at}
        return base64.b64encode(json.dumps(cursor_data).encode()).decode()
    
    def _get_user(self, user_id: int) -> User:
        """Получить пользователя"""
        return self.db.query(User).filter(User.id == user_id).first()
    
    def _is_channel_member(self, user_id: int, channel_id: int) -> bool:
        """Проверить, является ли пользователь участником канала"""
        from app.models.community_member import ChannelMember
        count = self.db.query(ChannelMember).filter(
            ChannelMember.user_id == user_id,
            ChannelMember.channel_id == channel_id
        ).count()
        return count > 0
    
    def _enrich_posts(self, posts: List[Post], user_id: int) -> List[dict]:
        """Обогатить посты метаданными (лайки, комментарии, автор, репосты) - оптимизировано с batch loading"""
        from app.models.like import Like
        from app.models.comment import Comment
        from app.models.repost import Repost
        from app.models.saved_post import SavedPost
        from app.models.community import Channel
        from app.models.follower import Follower
        from sqlalchemy import func
        
        if not posts:
            return []
        
        # Batch loading - загружаем все данные одним запросом
        post_ids = [p.id for p in posts]
        user_ids = list(set([p.user_id for p in posts]))
        channel_ids = list(set([p.channel_id for p in posts if p.channel_id]))
        
        # 1. Загружаем все счетчики лайков одним запросом
        likes_counts = self.db.query(
            Like.post_id,
            func.count(Like.id).label('count')
        ).filter(
            Like.post_id.in_(post_ids)
        ).group_by(Like.post_id).all()
        likes_counts_dict = {row.post_id: row.count for row in likes_counts}
        
        # 2. Загружаем все счетчики комментариев одним запросом
        comments_counts = self.db.query(
            Comment.post_id,
            func.count(Comment.id).label('count')
        ).filter(
            Comment.post_id.in_(post_ids),
            Comment.deleted_at.is_(None)
        ).group_by(Comment.post_id).all()
        comments_counts_dict = {row.post_id: row.count for row in comments_counts}
        
        # 3. Загружаем все счетчики репостов одним запросом
        reposts_counts = self.db.query(
            Repost.post_id,
            func.count(Repost.id).label('count')
        ).filter(
            Repost.post_id.in_(post_ids)
        ).group_by(Repost.post_id).all()
        reposts_counts_dict = {row.post_id: row.count for row in reposts_counts}
        
        # 4. Загружаем все лайки пользователя одним запросом
        user_likes = self.db.query(Like.post_id).filter(
            Like.user_id == user_id,
            Like.post_id.in_(post_ids)
        ).all()
        user_liked_post_ids = {row.post_id for row in user_likes}
        
        # 5. Загружаем все репосты пользователя одним запросом
        user_reposts = self.db.query(Repost.post_id).filter(
            Repost.user_id == user_id,
            Repost.post_id.in_(post_ids)
        ).all()
        user_reposted_post_ids = {row.post_id for row in user_reposts}

        user_saved_rows = self.db.query(SavedPost.post_id).filter(
            SavedPost.user_id == user_id,
            SavedPost.post_id.in_(post_ids),
        ).all()
        user_saved_post_ids = {row[0] for row in user_saved_rows}
        
        # 6. Загружаем всех авторов одним запросом
        authors = self.db.query(User).filter(User.id.in_(user_ids)).all()
        authors_dict = {author.id: author for author in authors}
        
        # 7. Загружаем все каналы одним запросом
        channels_dict = {}
        if channel_ids:
            channels = self.db.query(Channel).filter(Channel.id.in_(channel_ids)).all()
            channels_dict = {channel.id: channel for channel in channels}
        
        # 8. Загружаем подписки пользователя
        following_ids = [f.followee_id for f in self.db.query(Follower).filter(
            Follower.follower_id == user_id
        ).all()]
        check_user_ids = following_ids + [user_id]
        
        # 9. Репост от подписок / себя: кто последний репостнул и текст комментария к репосту
        reposted_by_dict = {}
        if check_user_ids and post_ids:
            all_repost_rows = (
                self.db.query(
                    Repost.post_id,
                    Repost.user_id,
                    Repost.comment,
                    Repost.created_at,
                )
                .filter(
                    Repost.post_id.in_(post_ids),
                    Repost.user_id.in_(check_user_ids),
                )
                .all()
            )
            by_post: dict = {}
            for r in all_repost_rows:
                by_post.setdefault(r.post_id, []).append(r)
            for post_id, rows in by_post.items():
                best = max(rows, key=lambda x: x.created_at)
                reposter = authors_dict.get(best.user_id)
                if reposter:
                    entry = {
                        "id": reposter.id,
                        "name": reposter.name,
                        "username": reposter.username,
                        "avatar_url": reposter.avatar_url,
                    }
                    if best.comment and str(best.comment).strip():
                        entry["comment"] = str(best.comment).strip()
                    reposted_by_dict[post_id] = entry
        
        # Формируем результат
        enriched = []
        for post in posts:
            author = authors_dict.get(post.user_id)
            channel = channels_dict.get(post.channel_id) if post.channel_id else None
            
            enriched.append({
                "id": post.id,
                "type": post.type,
                "title": post.title,
                "description": post.description,
                "status": post.status,
                "created_at": post.created_at.isoformat() if post.created_at else None,
                "published_at": post.published_at.isoformat() if post.published_at else None,
                "user_id": post.user_id,
                "channel_id": post.channel_id,
                "community_id": post.channel_id,  # Для обратной совместимости
                "is_promoted": bool(getattr(post, "is_promoted", False)),
                "body": post.body,
                "tags": post.tags,
                "likes_count": likes_counts_dict.get(post.id, 0),
                "comments_count": comments_counts_dict.get(post.id, 0),
                "reposts_count": reposts_counts_dict.get(post.id, 0),
                "is_liked": post.id in user_liked_post_ids,
                "is_saved": post.id in user_saved_post_ids,
                "is_reposted": post.id in user_reposted_post_ids,
                "author": {
                    "id": author.id if author else None,
                    "name": author.name if author else None,
                    "username": author.username if author else None,
                    "avatar_url": author.avatar_url if author else None,
                } if author else None,
                "reposted_by": reposted_by_dict.get(post.id),  # Информация о том, кто репостнул
                "channel": {
                    "id": channel.id,
                    "name": channel.name,
                    "slug": channel.slug,
                    "avatar_url": channel.avatar_url,
                    "description": channel.description,
                } if channel else None,  # Информация о канале
            })
        
        return enriched
    
    def _serialize_feed_cache(self, cache_data: Dict[str, Any]) -> Optional[bytes]:
        """
        Сериализовать данные кэша фида для Redis
        
        Args:
            cache_data: Словарь с данными для кэширования
            
        Returns:
            Сериализованные данные (bytes) или None при ошибке
        """
        try:
            # Используем JSON для сериализации (легче отлаживать, чем pickle)
            json_str = json.dumps(cache_data, default=str)  # default=str для datetime
            return json_str.encode('utf-8')
        except Exception as e:
            logger.warning(f"Failed to serialize feed cache: {e}")
            return None
    
    def _deserialize_feed_cache(self, cached_data) -> Optional[Dict[str, Any]]:
        """
        Десериализовать данные кэша фида из Redis
        
        Args:
            cached_data: Сериализованные данные (bytes или str)
            
        Returns:
            Словарь с данными кэша или None при ошибке
        """
        try:
            # Redis может возвращать данные как bytes или str в зависимости от настроек
            if isinstance(cached_data, bytes):
                json_str = cached_data.decode('utf-8')
            elif isinstance(cached_data, str):
                json_str = cached_data
            else:
                logger.warning(f"Unexpected cache data type: {type(cached_data)}")
                return None
            return json.loads(json_str)
        except Exception as e:
            logger.warning(f"Failed to deserialize feed cache: {e}")
            return None
    
    def invalidate_feed_cache(self, user_id: int, feed_type: Optional[str] = None):
        """
        Инвалидировать кэш фида для пользователя
        
        Args:
            user_id: ID пользователя
            feed_type: Тип фида (если None, инвалидирует все типы)
        """
        try:
            feed_types = (
                [feed_type] if feed_type else ["all", "reels", "recipes", "photos"]
            )
            for ft in feed_types:
                for following_only in (True, False):
                    for hide_promo in (True, False):
                        self.redis.delete(
                            f"feed:{user_id}:{ft}:following_only={following_only}"
                            f":hide_promo={hide_promo}"
                        )
                    # legacy key (до hide_promo в ключе)
                    self.redis.delete(
                        f"feed:{user_id}:{ft}:following_only={following_only}"
                    )
            logger.debug(f"Invalidated feed cache for user {user_id}")
        except Exception as e:
            logger.warning(f"Failed to invalidate feed cache: {e}")

