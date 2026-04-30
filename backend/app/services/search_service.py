"""
Сервис для полнотекстового поиска
"""
from sqlalchemy.orm import Session
from sqlalchemy import func, or_, and_, text
import sqlalchemy as sa
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
from app.models.post import Post
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
        # Подготавливаем поисковый запрос для PostgreSQL
        search_query = self._prepare_search_query(query)
        
        # Базовый запрос
        base_query = self.db.query(Post).filter(
            Post.status == "published",
            Post.deleted_at.is_(None),
            Post.visibility.in_(["public", "followers"])
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
        
        # Фильтр по тегам (посты должны содержать хотя бы один тег)
        if tags:
            # Используем оператор && для проверки пересечения массивов
            base_query = base_query.filter(Post.tags.op('&&')(tags))
        
        # Фильтр по дате публикации
        if date_from:
            base_query = base_query.filter(Post.published_at >= date_from)
        if date_to:
            base_query = base_query.filter(Post.published_at <= date_to)
        
        # Полнотекстовый поиск
        # Создаем комбинированный tsvector для поиска
        # Ищем в title, description, tags и body (для рецептов)
        
        # Базовый tsvector для всех постов
        search_vector = func.to_tsvector('russian',
            func.coalesce(Post.title, '') + ' ' +
            func.coalesce(Post.description, '') + ' ' +
            func.array_to_string(func.coalesce(Post.tags, []), ' ')
        )
        
        # Для рецептов добавляем текст из body (ingredients и steps)
        if post_type == "recipe" or post_type is None:
            # Извлекаем текст из JSON body для рецептов
            ingredients_text = func.coalesce(
                func.cast(Post.body['ingredients'], sa.Text), ''
            )
            steps_text = func.coalesce(
                func.cast(Post.body['steps'], sa.Text), ''
            )
            
            search_vector = func.to_tsvector('russian',
                func.coalesce(Post.title, '') + ' ' +
                func.coalesce(Post.description, '') + ' ' +
                func.array_to_string(func.coalesce(Post.tags, []), ' ') + ' ' +
                func.coalesce(ingredients_text, '') + ' ' +
                func.coalesce(steps_text, '')
            )
        
        # Применяем поиск используя оператор @@
        search_query_ts = func.to_tsquery('russian', search_query)
        base_query = base_query.filter(search_vector.op('@@')(search_query_ts))
        
        # Подсчет релевантности (rank)
        # Используем ts_rank_cd для ранжирования результатов
        rank_expr = func.ts_rank_cd(search_vector, search_query_ts)
        
        # Сортируем по релевантности
        base_query = base_query.order_by(rank_expr.desc(), Post.published_at.desc())
        
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
    
    def _prepare_search_query(self, query: str) -> str:
        """
        Подготовить поисковый запрос для PostgreSQL tsquery
        
        Преобразует обычный запрос в формат tsquery:
        - Разбивает на слова
        - Добавляет операторы & (AND) или | (OR)
        - Экранирует специальные символы
        """
        # Удаляем лишние пробелы
        query = query.strip()
        
        # Разбиваем на слова
        words = query.split()
        
        if not words:
            return ""
        
        # Экранируем специальные символы и объединяем через &
        # Используем & для поиска всех слов (AND логика)
        escaped_words = []
        for word in words:
            # Экранируем специальные символы tsquery
            escaped = word.replace(':', '\\:').replace('&', '\\&').replace('|', '\\|')
            escaped_words.append(escaped)
        
        # Объединяем через & (все слова должны присутствовать)
        return ' & '.join(escaped_words)
    
    
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
            Post.deleted_at.is_(None)
        ).distinct().all()
        
        query_lower = query.lower()
        for tag_list in tags:
            if tag_list[0]:  # Проверяем, что теги не None
                for tag in tag_list[0]:
                    if query_lower in tag.lower() and tag not in suggestions:
                        suggestions.append(tag)
                        if len(suggestions) >= limit:
                            break
        
        # Предложения из названий постов
        if len(suggestions) < limit:
            titles = self.db.query(Post.title).filter(
                Post.status == "published",
                Post.deleted_at.is_(None),
                Post.title.ilike(f"%{query}%")
            ).distinct().limit(limit - len(suggestions)).all()
            
            for title_tuple in titles:
                if title_tuple[0] and title_tuple[0] not in suggestions:
                    suggestions.append(title_tuple[0])
                    if len(suggestions) >= limit:
                        break
        
        return suggestions[:limit]

