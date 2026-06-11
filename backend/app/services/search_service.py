"""Сервис для полнотекстового поиска."""
from sqlalchemy.orm import Session
from sqlalchemy import func, or_, and_
import sqlalchemy as sa
from typing import List, Dict, Any, Optional
from datetime import datetime
from app.models.post import Post
from app.services.feed_service import FeedService
from app.services.search_normalization import (
    escaped_like_pattern,
    search_terms,
    stable_search_key,
)
from app.models.user import User


class SearchService:
    """Сервис для полнотекстового поиска по постам и рецептам"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def search_posts(
        self,
        query: str,
        user_id: Optional[int] = None,
        post_type: Optional[str] = None,
        author_id: Optional[int] = None,
        channel_id: Optional[int] = None,
        tags: Optional[List[str]] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        min_likes: Optional[int] = None,
        min_comments: Optional[int] = None,
        sort_by: str = "relevance",  # relevance | date | popularity
        following_only: bool = False,
        limit: int = 20,
        offset: int = 0
    ) -> Dict[str, Any]:
        """
        Полнотекстовый поиск по постам
        
        Args:
            query: Поисковый запрос
            user_id: ID пользователя (для фильтрации приватных постов)
            post_type: Тип поста (photo, recipe, reel, text)
            author_id: ID автора (для фильтрации по автору)
            channel_id: ID канала (для фильтрации по каналу)
            tags: Список тегов (посты должны содержать хотя бы один тег)
            date_from: Начальная дата публикации
            date_to: Конечная дата публикации
            min_likes: Минимальное количество лайков
            min_comments: Минимальное количество комментариев
            sort_by: Сортировка (relevance | date | popularity)
            limit: Количество результатов
            offset: Смещение для пагинации
        """
        # Подготавливаем поисковый запрос как обычный пользовательский текст.
        # websearch_to_tsquery не падает на #, @, дефисах и других символах.
        search_query = self._prepare_search_query(query)
        search_terms = self._search_terms(query)
        if not search_query and not search_terms:
            return {
                "items": [],
                "total": 0,
                "limit": limit,
                "offset": offset,
                "has_more": False,
            }
        
        # Базовый запрос
        base_query = self.db.query(Post).filter(
            Post.status == "published",
            Post.deleted_at.is_(None),
            Post.visibility.in_(["public", "followers"]),
            *FeedService._recommendation_post_filters(),
        )
        
        # Фильтр по типу
        if post_type:
            base_query = base_query.filter(Post.type == post_type)
        
        # Фильтр по автору
        if author_id:
            base_query = base_query.filter(Post.user_id == author_id)
        
        # Фильтр по каналу
        if channel_id:
            base_query = base_query.filter(Post.channel_id == channel_id)

        if following_only and user_id:
            base_query = base_query.filter(
                self._following_scope_filter(user_id)
            )
        elif following_only:
            return {
                "items": [],
                "total": 0,
                "limit": limit,
                "offset": offset,
                "has_more": False,
            }
        
        # Фильтр по тегам (посты должны содержать хотя бы один тег)
        if tags:
            # Используем оператор && для проверки пересечения массивов
            base_query = base_query.filter(Post.tags.op('&&')(tags))
        
        # Фильтр по дате публикации
        if date_from:
            base_query = base_query.filter(Post.published_at >= date_from)
        if date_to:
            base_query = base_query.filter(Post.published_at <= date_to)

        from app.models.like import Like
        from app.models.comment import Comment

        likes_count_expr = (
            self.db.query(func.count(Like.id))
            .filter(Like.post_id == Post.id)
            .correlate(Post)
            .scalar_subquery()
        )
        comments_count_expr = (
            self.db.query(func.count(Comment.id))
            .filter(Comment.post_id == Post.id, Comment.deleted_at.is_(None))
            .correlate(Post)
            .scalar_subquery()
        )

        if min_likes is not None:
            base_query = base_query.filter(likes_count_expr >= min_likes)
        if min_comments is not None:
            base_query = base_query.filter(comments_count_expr >= min_comments)
        
        # Полнотекстовый поиск
        # Создаем комбинированный tsvector для поиска
        # Ищем в title, description, tags и body (для рецептов)
        
        tags_text = func.coalesce(func.array_to_string(Post.tags, ' '), '')
        ingredients_text = func.coalesce(
            func.cast(Post.body['ingredients'], sa.Text), ''
        )
        steps_text = func.coalesce(
            func.cast(Post.body['steps'], sa.Text), ''
        )

        # Базовый tsvector для всех постов
        search_vector = func.to_tsvector('russian',
            func.coalesce(Post.title, '') + ' ' +
            func.coalesce(Post.description, '') + ' ' +
            tags_text
        )
        
        # Для рецептов добавляем текст из body (ingredients и steps)
        if post_type == "recipe" or post_type is None:
            search_vector = func.to_tsvector('russian',
                func.coalesce(Post.title, '') + ' ' +
                func.coalesce(Post.description, '') + ' ' +
                tags_text + ' ' +
                func.coalesce(ingredients_text, '') + ' ' +
                func.coalesce(steps_text, '')
            )
        
        # Применяем полнотекстовый поиск и fallback по подстрокам:
        # FTS хорошо ранжирует слова, fallback ловит частичные названия,
        # хештеги, латиницу и пользовательские запросы с символами.
        search_query_ts = func.websearch_to_tsquery('russian', search_query)
        text_match_filters = [
            self._term_match_filter(term, tags_text, ingredients_text, steps_text)
            for term in search_terms
        ]
        fallback_filter = and_(*text_match_filters) if text_match_filters else None
        if fallback_filter is not None:
            base_query = base_query.filter(
                or_(search_vector.op('@@')(search_query_ts), fallback_filter)
            )
        else:
            base_query = base_query.filter(search_vector.op('@@')(search_query_ts))
        
        # Подсчет релевантности (rank)
        # Используем ts_rank_cd для ранжирования результатов
        rank_expr = func.ts_rank_cd(search_vector, search_query_ts)
        
        if sort_by == "date":
            base_query = base_query.order_by(Post.published_at.desc())
        elif sort_by == "popularity":
            base_query = base_query.order_by(
                likes_count_expr.desc(),
                comments_count_expr.desc(),
                Post.published_at.desc(),
            )
        else:
            base_query = base_query.order_by(
                rank_expr.desc(),
                likes_count_expr.desc(),
                Post.published_at.desc(),
            )
        
        # Подсчет общего количества результатов
        total_count = base_query.count()
        
        # Получаем результаты с пагинацией и eager loading (оптимизация для 100k пользователей)
        from sqlalchemy.orm import joinedload, selectinload
        posts = base_query.options(
            joinedload(Post.user),
            selectinload(Post.channel)
        ).offset(offset).limit(limit).all()
        
        # Обогащаем посты метаданными
        enriched_posts = self._enrich_posts(posts, user_id)
        
        return {
            "items": enriched_posts,
            "total": total_count,
            "limit": limit,
            "offset": offset,
            "has_more": (offset + limit) < total_count
        }
    
    def _following_scope_filter(self, user_id: int):
        """Посты только от подписок и каналов пользователя."""
        from app.models.follower import Follower
        from app.models.community_member import ChannelMember
        from app.models.community import Channel
        from app.services.channel_membership_service import MEMBER_STATUS_ACTIVE

        following_ids = [
            row[0]
            for row in self.db.query(Follower.followee_id).filter(
                Follower.follower_id == user_id
            ).all()
        ]
        subscribed_channel_ids = [
            row[0]
            for row in self.db.query(ChannelMember.channel_id).filter(
                ChannelMember.user_id == user_id,
                ChannelMember.status == MEMBER_STATUS_ACTIVE,
            ).all()
        ]
        owned_channel_ids = [
            row[0]
            for row in self.db.query(Channel.id).filter(
                Channel.admin_user_id == user_id
            ).all()
        ]
        all_channel_ids = list(set(subscribed_channel_ids + owned_channel_ids))

        conditions = []
        if following_ids:
            conditions.append(
                and_(
                    Post.user_id.in_(following_ids),
                    Post.visibility.in_(["public", "followers"]),
                )
            )
        if all_channel_ids:
            conditions.append(
                and_(
                    Post.channel_id.in_(all_channel_ids),
                    Post.channel_id.isnot(None),
                )
            )
        if not conditions:
            return Post.id == -1
        return or_(*conditions)

    def _prepare_search_query(self, query: str) -> str:
        """
        Подготовить поисковый запрос для PostgreSQL tsquery
        
        Преобразует обычный запрос в безопасный текст для websearch_to_tsquery.
        Слова вроде #tag и @user ищутся как tag/user, а не ломают SQL-запрос.
        """
        return stable_search_key(query)

    def _search_terms(self, query: str) -> List[str]:
        return search_terms(query)

    def _term_match_filter(self, term: str, tags_text, ingredients_text, steps_text):
        pattern = escaped_like_pattern(term)
        return or_(
            func.coalesce(Post.title, '').ilike(pattern, escape='\\'),
            func.coalesce(Post.description, '').ilike(pattern, escape='\\'),
            tags_text.ilike(pattern, escape='\\'),
            ingredients_text.ilike(pattern, escape='\\'),
            steps_text.ilike(pattern, escape='\\'),
        )
    
    
    def _enrich_posts(self, posts: List[Post], user_id: Optional[int]) -> List[Dict[str, Any]]:
        """Обогатить посты метаданными (оптимизировано для 100k пользователей)"""
        if not posts:
            return []
        
        from app.models.like import Like
        from app.models.comment import Comment
        from app.models.repost import Repost
        from sqlalchemy import func
        
        post_ids = [p.id for p in posts]
        
        # Batch loading: получаем все счетчики одним запросом
        likes_data = self.db.query(Like.post_id, func.count(Like.id).label('count')).filter(
            Like.post_id.in_(post_ids)
        ).group_by(Like.post_id).all()
        likes_count_map = {item.post_id: item.count for item in likes_data}
        
        comments_data = self.db.query(Comment.post_id, func.count(Comment.id).label('count')).filter(
            Comment.post_id.in_(post_ids),
            Comment.deleted_at.is_(None)
        ).group_by(Comment.post_id).all()
        comments_count_map = {item.post_id: item.count for item in comments_data}
        
        reposts_data = self.db.query(Repost.post_id, func.count(Repost.id).label('count')).filter(
            Repost.post_id.in_(post_ids)
        ).group_by(Repost.post_id).all()
        reposts_count_map = {item.post_id: item.count for item in reposts_data}
        
        # Batch loading: проверяем лайки пользователя одним запросом
        user_liked_post_ids = set()
        if user_id:
            user_likes = self.db.query(Like.post_id).filter(
                Like.user_id == user_id,
                Like.post_id.in_(post_ids)
            ).all()
            user_liked_post_ids = {item.post_id for item in user_likes}
        
        # Batch loading: загружаем всех авторов одним запросом
        all_user_ids = list(set([p.user_id for p in posts]))
        users_map = {u.id: u for u in self.db.query(User).filter(User.id.in_(all_user_ids)).all()}
        
        enriched = []
        for post in posts:
            author = users_map.get(post.user_id)
            
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
                "body": post.body,
                "tags": post.tags,
                "likes_count": likes_count_map.get(post.id, 0),
                "comments_count": comments_count_map.get(post.id, 0),
                "reposts_count": reposts_count_map.get(post.id, 0),
                "is_liked": post.id in user_liked_post_ids,
                "author": {
                    "id": author.id if author else None,
                    "name": author.name if author else None,
                    "username": author.username if author else None,
                    "avatar_url": author.avatar_url if author else None,
                } if author else None,
            })
        
        return enriched
    
    def search_recipes(
        self,
        query: str,
        user_id: Optional[int] = None,
        author_id: Optional[int] = None,
        tags: Optional[List[str]] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        min_likes: Optional[int] = None,
        min_comments: Optional[int] = None,
        sort_by: str = "relevance",
        limit: int = 20,
        offset: int = 0
    ) -> Dict[str, Any]:
        """
        Поиск по рецептам (специализированный метод)
        
        Ищет в:
        - Названии рецепта (title)
        - Описании (description)
        - Ингредиентах (body.ingredients)
        - Шагах приготовления (body.steps)
        - Тегах (tags)
        """
        return self.search_posts(
            query=query,
            user_id=user_id,
            post_type="recipe",
            author_id=author_id,
            tags=tags,
            date_from=date_from,
            date_to=date_to,
            min_likes=min_likes,
            min_comments=min_comments,
            sort_by=sort_by,
            limit=limit,
            offset=offset
        )
    
    def get_search_suggestions(
        self,
        query: str,
        limit: int = 10
    ) -> List[str]:
        """
        Получить предложения для автодополнения поиска
        
        Ищет похожие теги, названия постов и ингредиенты
        """
        if len(query) < 2:
            return []
        
        suggestions = []
        
        # Предложения из тегов
        tags = self.db.query(Post.tags).filter(
            Post.status == "published",
            Post.deleted_at.is_(None),
            *FeedService._recommendation_post_filters(),
        ).distinct().all()
        
        query_lower = stable_search_key(query)
        if len(query_lower) < 2:
            return []
        for tag_list in tags:
            if tag_list[0]:  # Проверяем, что теги не None
                for tag in tag_list[0]:
                    if query_lower in stable_search_key(tag) and tag not in suggestions:
                        suggestions.append(tag)
                        if len(suggestions) >= limit:
                            break
        
        # Предложения из названий постов
        if len(suggestions) < limit:
            titles = self.db.query(Post.title).filter(
                Post.status == "published",
                Post.deleted_at.is_(None),
                func.coalesce(Post.title, '').ilike(
                    escaped_like_pattern(query_lower), escape='\\'
                ),
                *FeedService._recommendation_post_filters(),
            ).distinct().limit(limit - len(suggestions)).all()
            
            for title_tuple in titles:
                if title_tuple[0] and title_tuple[0] not in suggestions:
                    suggestions.append(title_tuple[0])
                    if len(suggestions) >= limit:
                        break
        
        return suggestions[:limit]

