"""
API для работы с рецептами и рекомендациями
"""
from fastapi import APIRouter, Query, HTTPException, Body, Depends
from fastapi.responses import Response
from typing import Optional, List, Dict, Any
import os
import json
import time
import base64
import requests
import asyncio
import concurrent.futures
import logging
import hashlib
from sqlalchemy.orm import Session
from redis.exceptions import ConnectionError as RedisConnectionError, TimeoutError as RedisTimeoutError
from app.core.config import settings
from app.core.redis_client import get_redis, redis_client
from app.core.database import get_db
from app.models.post import Post
from app.models.community import Channel
from app.models.base_recipe import BaseRecipe

logger = logging.getLogger(__name__)

# Попытка импортировать библиотеку для перевода
TRANSLATOR_AVAILABLE = False
GoogleTranslator = None
Translator = None

try:
    from deep_translator import GoogleTranslator
    TRANSLATOR_AVAILABLE = True
    print("✅ deep-translator доступен для переводов")
except ImportError:
    try:
        from googletrans import Translator
        TRANSLATOR_AVAILABLE = True
        Translator = Translator()
        print("✅ googletrans доступен для переводов")
    except (ImportError, AttributeError) as e:
        print(f"⚠️ Переводчик не установлен: {e}")
        TRANSLATOR_AVAILABLE = False

router = APIRouter()

# Получаем API ключ Spoonacular из настроек
SPOONACULAR_API_KEY = settings.SPOONACULAR_API_KEY

# Константы
CACHE_TTL = 12 * 3600  # 12 hours cache
DEFAULT_LANGUAGE = "ru"
DEFAULT_MODE = "all"
ALLOWED_MODES = {"recipe", "calories", "all"}
MAX_HISTORY_ENTRIES = 50


def parse_steps(recipe_data: dict) -> List[dict]:
    """Парсит шаги приготовления из данных Spoonacular"""
    steps = []
    if "analyzedInstructions" in recipe_data and recipe_data["analyzedInstructions"]:
        for instruction in recipe_data["analyzedInstructions"]:
            if "steps" in instruction:
                for step in instruction["steps"]:
                    steps.append({
                        "number": step.get("number", 0),
                        "step": step.get("step", ""),
                        "instruction": step.get("step", ""),  # Дублируем для совместимости
                    })
    return steps


def strip_html_tags(text: str) -> str:
    """Удаляет HTML теги из текста"""
    if not text:
        return ""
    import re
    return re.sub(r'<[^>]+>', '', text)


def normalize_mode(raw: Optional[str]) -> str:
    """Нормализует режим анализа"""
    if not raw:
        return DEFAULT_MODE
    value = raw.strip().lower()
    if value not in ALLOWED_MODES:
        return DEFAULT_MODE
    return value


def build_proxy(image_url: str) -> str:
    """Создает прокси URL для изображения (пока возвращает оригинал)"""
    return image_url


def get_user_settings() -> Dict[str, str]:
    """Получить настройки пользователя из Redis"""
    try:
        settings_json = redis_client.get("user_settings")
        if settings_json:
            return json.loads(settings_json)
    except Exception:
        pass
    return {"analysis_mode": DEFAULT_MODE, "language": DEFAULT_LANGUAGE}


def save_user_settings(settings: Dict[str, str]):
    """Сохранить настройки пользователя в Redis"""
    try:
        redis_client.set("user_settings", json.dumps(settings, ensure_ascii=False))
    except Exception:
        pass


def get_cached_translation(text: str, target_lang: str) -> Optional[str]:
    """Получить перевод из кеша Redis"""
    if not text or target_lang == "en":
        return None
    
    try:
        cache_key = f"translation:{hashlib.md5(f'{text}:{target_lang}'.encode()).hexdigest()}"
        cached = redis_client.get(cache_key)
        if cached:
            return cached.decode('utf-8')
    except Exception as e:
        print(f"⚠️ Redis translation cache read error: {e}")
    return None


def cache_translation(text: str, target_lang: str, translated: str):
    """Сохранить перевод в кеш Redis"""
    if not text or not translated or target_lang == "en":
        return
    
    try:
        cache_key = f"translation:{hashlib.md5(f'{text}:{target_lang}'.encode()).hexdigest()}"
        redis_client.setex(cache_key, 86400 * 30, translated)  # 30 дней
    except Exception as e:
        print(f"⚠️ Redis translation cache write error: {e}")


def translate_text(text: str, target_lang: str, max_retries: int = 3) -> str:
    """Переводит текст на целевой язык с улучшенным качеством и повторными попытками"""
    if not text or not target_lang or target_lang == "en":
        return text
    
    if not TRANSLATOR_AVAILABLE:
        return text
    
    # Проверяем кеш перед переводом
    cached = get_cached_translation(text, target_lang)
    if cached:
        return cached
    
    import time
    import random
    
    translated = text  # По умолчанию возвращаем оригинал
    
    # Повторные попытки для обработки ошибок соединения
    for attempt in range(max_retries):
        try:
            # Пробуем deep_translator (более точный)
            if GoogleTranslator is not None:
                translator = GoogleTranslator(source='auto', target=target_lang)
                # Разбиваем длинные тексты на предложения для лучшего перевода
                if len(text) > 500:
                    sentences = text.split('. ')
                    translated_sentences = []
                    for sentence in sentences:
                        if sentence.strip():
                            try:
                                # Проверяем кеш для каждого предложения
                                cached_sentence = get_cached_translation(sentence.strip(), target_lang)
                                if cached_sentence:
                                    translated_sentences.append(cached_sentence)
                                else:
                                    translated = translator.translate(sentence.strip())
                                    cache_translation(sentence.strip(), target_lang, translated)
                                    translated_sentences.append(translated)
                            except Exception as e:
                                # Если ошибка при переводе предложения, оставляем оригинал
                                if attempt == max_retries - 1:
                                    translated_sentences.append(sentence.strip())
                                else:
                                    raise
                    translated = '. '.join(translated_sentences)
                else:
                    translated = translator.translate(text)
                break
            # Пробуем googletrans
            elif Translator is not None:
                result = Translator.translate(text, dest=target_lang)
                translated = result.text
                break
        except Exception as e:
            error_str = str(e)
            # Проверяем, является ли это ошибкой соединения
            is_connection_error = (
                'Connection aborted' in error_str or
                'ConnectionResetError' in error_str or
                'Connection refused' in error_str or
                'Failed to fetch' in error_str or
                'timeout' in error_str.lower()
            )
            
            if is_connection_error and attempt < max_retries - 1:
                # Ждем перед повторной попыткой (экспоненциальная задержка)
                wait_time = (2 ** attempt) + random.uniform(0, 1)
                print(f"⚠️ Translation connection error (attempt {attempt + 1}/{max_retries}), retrying in {wait_time:.1f}s...")
                time.sleep(wait_time)
                continue
            else:
                # Если это не ошибка соединения или последняя попытка, просто логируем
                if attempt == max_retries - 1:
                    print(f"⚠️ Translation error for '{text[:30]}...' (after {max_retries} attempts): {e}")
                else:
                    print(f"⚠️ Translation error for '{text[:30]}...' (attempt {attempt + 1}/{max_retries}): {e}")
    
    # Сохраняем в кеш, если перевод успешен
    if translated and translated != text:
        cache_translation(text, target_lang, translated)
    
    # Если все попытки не удались, возвращаем оригинальный текст
    return translated

def translate_list(items: List[str], target_lang: str) -> List[str]:
    """Переводит список строк с кешированием"""
    if not items or not target_lang or target_lang == "en":
        return items
    
    return [translate_text(item, target_lang) for item in items]

def translate_steps(steps: List[Dict], target_lang: str) -> List[Dict]:
    """Переводит шаги приготовления с кешированием"""
    if not steps or not target_lang or target_lang == "en":
        return steps
    
    translated = []
    for step in steps:
        step_text = step.get("step", "") or step.get("instruction", "")
        translated_text = translate_text(step_text, target_lang)
        translated.append({
            "number": step.get("number", len(translated) + 1),
            "step": translated_text,
            "instruction": translated_text,
            "image": step.get("image")
        })
    return translated

def store_history_entry(query: str, filters: Optional[Dict], mode: str):
    """Добавить запрос в историю"""
    try:
        entry = {
            "query": query,
            "filters": filters or {},
            "mode": mode,
            "ts": int(time.time()),
        }
        # Добавляем в список истории
        history_key = "search_history"
        history_json = redis_client.get(history_key) or "[]"
        history = json.loads(history_json)
        history.append(entry)
        # Ограничиваем количество записей
        history = sorted(history, key=lambda x: x.get("ts", 0), reverse=True)[:MAX_HISTORY_ENTRIES]
        redis_client.set(history_key, json.dumps(history, ensure_ascii=False))
    except Exception:
        pass


def search_base_recipes(
    query_text: str,
    db: Session,
    limit: int = 8
) -> List[Dict[str, Any]]:
    """
    Поиск в базовой базе русских рецептов
    Возвращает готовые рецепты без перевода
    """
    if not query_text or not query_text.strip():
        return []
    
    # Нормализуем запрос
    query_words = [word.strip().lower() for word in query_text.split() if word.strip()]
    if not query_words:
        return []
    
    # Поиск по названию, тегам и ключевым словам
    from sqlalchemy import func, or_, String, cast
    
    search_filters = []
    for word in query_words:
        # Поиск в названии
        search_filters.append(
            func.lower(BaseRecipe.title).contains(word)
        )
        # Поиск в тегах (JSON поле)
        search_filters.append(
            cast(BaseRecipe.tags, String).contains(word)
        )
        # Поиск в ключевых словах
        search_filters.append(
            cast(BaseRecipe.search_keywords, String).contains(word)
        )
    
    if not search_filters:
        return []
    
    # Выполняем запрос
    results = db.query(BaseRecipe).filter(
        or_(*search_filters)
    ).order_by(
        BaseRecipe.popularity_score.desc(),
        BaseRecipe.created_at.desc()
    ).limit(limit).all()
    
    recipes = []
    for recipe in results:
        # Форматируем ингредиенты
        ingredients = recipe.ingredients or []
        formatted_ingredients = []
        for ing in ingredients:
            if isinstance(ing, str):
                formatted_ingredients.append(ing)
            elif isinstance(ing, dict):
                formatted_ingredients.append(ing.get("name", "") or str(ing))
        
        # Форматируем шаги
        steps = recipe.steps or []
        formatted_steps = []
        for step in steps:
            if isinstance(step, dict):
                formatted_steps.append({
                    "number": step.get("number", len(formatted_steps) + 1),
                    "step": step.get("step") or step.get("instruction") or "",
                    "instruction": step.get("step") or step.get("instruction") or "",
                })
            elif isinstance(step, str):
                formatted_steps.append({
                    "number": len(formatted_steps) + 1,
                    "step": step,
                    "instruction": step,
                })
        
        # Подсчитываем релевантность (сколько слов совпало)
        matched_count = 0
        title_lower = (recipe.title or "").lower()
        for word in query_words:
            if word in title_lower:
                matched_count += 2
        
        recipe_dict = {
            "id": f"base_{recipe.id}",  # Префикс для идентификации
            "title": recipe.title,
            "image": recipe.image_url,
            "source_image": recipe.image_url,
            "ingredients": formatted_ingredients,
            "steps": formatted_steps,
            "usedIngredientCount": len(formatted_ingredients),
            "translated_title": recipe.title,  # Уже на русском
            "translated_ingredients": formatted_ingredients,  # Уже на русском
            "translated_steps": formatted_steps,  # Уже на русском
            "calories": recipe.calories,
            "nutrition": recipe.nutrition or {},
            "likes_count": 0,  # Можно добавить позже
            "meal_plan_count": 0,  # Можно добавить позже
            "source": "base",  # Идентификатор источника
            "relevance_score": matched_count,
        }
        recipes.append(recipe_dict)
    
    # Сортируем по релевантности
    recipes.sort(key=lambda x: x.get("relevance_score", 0), reverse=True)
    
    return recipes


def search_user_recipes(
    query_text: str,
    db: Session,
    limit: int = 10
) -> List[Dict[str, Any]]:
    """
    Поиск рецептов из каналов и профилей пользователей по любому тексту
    
    Ищет рецепты по:
    - Названию
    - Описанию
    - Ингредиентам
    - Тегам
    """
    from sqlalchemy import func, or_
    from app.models.like import Like
    
    # Нормализуем запрос - разбиваем на слова
    query_words = [word.strip().lower() for word in query_text.split() if word.strip()]
    if not query_words:
        return []
    
    # Также проверяем, может быть это список ингредиентов через запятую
    ingredient_list = [ing.strip().lower() for ing in query_text.split(',') if ing.strip()]
    # Объединяем все слова для поиска
    all_search_terms = list(set(query_words + ingredient_list))
    
    # Получаем рецепты из каналов и профилей (channel_id может быть NULL для профильных рецептов)
    query = db.query(
        Post,
        func.count(Like.id).label('likes_count')
    ).outerjoin(
        Like, Post.id == Like.post_id
    ).filter(
        Post.type == "recipe",
        Post.status == "published",
        Post.deleted_at.is_(None),
        # Проверяем, что канал разрешает публикацию в Menu (или это профильный рецепт)
        or_(
            Post.channel_id.is_(None),  # Профильные рецепты
            Post.channel_id.isnot(None)  # Рецепты из каналов (проверка auto_publish_to_menu будет ниже)
        )
    ).group_by(Post.id)
    
    # Фильтруем по тексту запроса
    # Ищем рецепты, где хотя бы одно слово совпадает в названии, описании, ингредиентах или тегах
    search_filters = []
    for term in all_search_terms:
        # Ищем в названии
        search_filters.append(
            func.lower(Post.title).contains(term)
        )
        # Ищем в описании
        if Post.description:
            search_filters.append(
                func.lower(Post.description).contains(term)
            )
        # Ищем в JSON поле body->ingredients
        search_filters.append(
            func.lower(func.cast(Post.body, type_=db.String)).contains(term)
        )
        # Ищем в тегах
        if Post.tags:
            search_filters.append(
                func.cast(Post.tags, type_=db.String).contains(term)
            )
    
    if search_filters:
        query = query.filter(or_(*search_filters))
    
    # Сортируем по релевантности (matched_count будет добавлен позже), лайкам и дате
    # Пока сортируем по лайкам и дате, релевантность добавим в цикле
    results = query.order_by(
        func.count(Like.id).desc(),
        Post.published_at.desc()
    ).limit(limit * 2).all()  # Берем больше, чтобы потом отсортировать по релевантности
    
    recipes = []
    for post, likes_count in results:
        body = post.body or {}
        post_ingredients = body.get("ingredients", [])
        
        # Форматируем ингредиенты
        formatted_ingredients = []
        for ing in post_ingredients:
            if isinstance(ing, str):
                formatted_ingredients.append(ing)
            elif isinstance(ing, dict):
                formatted_ingredients.append(ing.get("name", "") or str(ing))
        
        # Подсчитываем количество совпавших слов/ингредиентов для релевантности
        matched_count = 0
        for term in all_search_terms:
            # Проверяем в названии
            if term in (post.title or "").lower():
                matched_count += 2  # Название важнее
            # Проверяем в описании
            if post.description and term in post.description.lower():
                matched_count += 1
            # Проверяем в ингредиентах
            for post_ing in formatted_ingredients:
                if term in post_ing.lower():
                    matched_count += 1
                    break
        
        # Форматируем шаги
        steps = body.get("steps", [])
        formatted_steps = []
        for i, step in enumerate(steps, 1):
            if isinstance(step, dict):
                formatted_steps.append({
                    "number": step.get("number", i),
                    "step": step.get("text", step.get("step", "")),
                    "instruction": step.get("text", step.get("step", "")),
                })
            elif isinstance(step, str):
                formatted_steps.append({
                    "number": i,
                    "step": step,
                    "instruction": step,
                })
        
        # Получаем изображение
        image = None
        media = body.get("media", [])
        if media:
            for item in media:
                if item.get("type") == "image" and item.get("url"):
                    image = item.get("url")
                    break
        
        # Проверяем настройки канала (если рецепт из канала)
        if post.channel_id:
            channel = db.query(Channel).filter(Channel.id == post.channel_id).first()
            if channel and not channel.auto_publish_to_menu:
                continue  # Пропускаем рецепты из каналов, где auto_publish_to_menu = false
        
        recipe_data = {
            "id": f"user_{post.id}",  # ID для рецептов пользователей
            "title": post.title or "Рецепт без названия",
            "image": image,
            "source_image": image,
            "usedIngredientCount": matched_count,  # Количество совпавших слов/ингредиентов
            "ingredients": formatted_ingredients,
            "steps": formatted_steps,
            "instructions_raw": "",
            "translated_title": post.title or "Рецепт без названия",
            "translated_ingredients": formatted_ingredients,
            "translated_steps": formatted_steps,
            "calories": body.get("calories"),
            "nutrition": None,
            "channel_id": post.channel_id,
            "user_id": post.user_id,
            "source": "user" if post.channel_id is None else "channel",
            "likes_count": likes_count or 0,
            "_relevance": matched_count,  # Для сортировки
        }
        recipes_with_relevance.append((recipe_data, matched_count))
    
    # Сортируем по релевантности и ограничиваем
    recipes_with_relevance.sort(key=lambda x: x[1], reverse=True)
    recipes = [r[0] for r in recipes_with_relevance[:limit]]
    
    return recipes


def get_channel_recipes_for_recommendations(
    db: Session,
    limit: int = 5,
    tags: Optional[str] = None,
    ingredients: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Получить рецепты из каналов и профилей для рекомендаций
    
    Возвращает популярные рецепты из каналов и профилей пользователей
    (по дате публикации и количеству лайков).
    """
    from app.models.like import Like
    from sqlalchemy import func, or_
    
    # Получаем рецепты из каналов и профилей с подсчетом лайков
    query = db.query(
        Post,
        func.count(Like.id).label('likes_count')
    ).outerjoin(
        Like, Post.id == Like.post_id
    ).filter(
        Post.type == "recipe",
        Post.status == "published",
        Post.deleted_at.is_(None),
        # Включаем рецепты из каналов (где auto_publish_to_menu = true) и профильные рецепты
        or_(
            Post.channel_id.is_(None),  # Профильные рецепты
            Post.channel_id.isnot(None)  # Рецепты из каналов
        )
    ).group_by(Post.id)
    
    # Фильтр по тегам (если указаны)
    if tags:
        tag_list = [t.strip().lower() for t in tags.split(',') if t.strip()]
        # Фильтруем по тегам в поле tags поста
        for tag in tag_list:
            query = query.filter(Post.tags.contains([tag]))
    
    # Фильтр по ингредиентам (если указаны)
    if ingredients:
        ingredient_list = [ing.strip().lower() for ing in ingredients.split(',') if ing.strip()]
        ingredient_filters = []
        for ing in ingredient_list:
            ingredient_filters.append(
                func.lower(func.cast(Post.body, type_=db.String)).contains(ing)
            )
            ingredient_filters.append(
                func.lower(Post.title).contains(ing)
            )
        if ingredient_filters:
            query = query.filter(or_(*ingredient_filters))
    
    # Сортируем и ограничиваем
    results = query.order_by(
        func.count(Like.id).desc(),
        Post.published_at.desc()
    ).limit(limit).all()
    
    recipes = []
    for post, likes_count in results:
        # Проверяем настройки канала (если рецепт из канала)
        if post.channel_id:
            channel = db.query(Channel).filter(Channel.id == post.channel_id).first()
            if channel and not channel.auto_publish_to_menu:
                continue  # Пропускаем рецепты из каналов, где auto_publish_to_menu = false
        body = post.body or {}
        steps = body.get("steps", [])
        formatted_steps = []
        for i, step in enumerate(steps, 1):
            if isinstance(step, dict):
                formatted_steps.append({
                    "number": step.get("number", i),
                    "step": step.get("text", step.get("step", "")),
                    "instruction": step.get("text", step.get("step", "")),
                })
            elif isinstance(step, str):
                formatted_steps.append({
                    "number": i,
                    "step": step,
                    "instruction": step,
                })
        
        formatted_ingredients = []
        for ing in body.get("ingredients", []):
            if isinstance(ing, str):
                formatted_ingredients.append(ing)
            elif isinstance(ing, dict):
                formatted_ingredients.append(ing.get("name", "") or str(ing))
        
        # Получаем изображение
        image = None
        media = body.get("media", [])
        if media:
            for item in media:
                if item.get("type") == "image" and item.get("url"):
                    image = item.get("url")
                    break
        
        recipe_data = {
            "id": f"user_{post.id}",  # ID для рецептов пользователей
            "title": post.title or "Рецепт без названия",
            "image": image,
            "source_image": image,
            "usedIngredientCount": 0,
            "ingredients": formatted_ingredients,
            "steps": formatted_steps,
            "instructions_raw": "",
            "translated_title": post.title or "Рецепт без названия",
            "translated_ingredients": formatted_ingredients,
            "translated_steps": formatted_steps,
            "calories": body.get("calories"),
            "nutrition": None,
            "channel_id": post.channel_id,
            "user_id": post.user_id,
            "source": "user" if post.channel_id is None else "channel",
            "likes_count": likes_count or 0,
        }
        recipes.append(recipe_data)
    
    return recipes


@router.get("/recommendations")
async def get_recommendations(
    limit: int = Query(6, ge=1, le=20, description="Количество рецептов"),
    tags: Optional[str] = Query(None, description="Теги для фильтрации"),
    ingredients: Optional[str] = Query(None, description="Ингредиенты"),
    mode: Optional[str] = Query(None, description="Режим анализа"),
    language: Optional[str] = Query("ru", description="Язык"),
    db: Session = Depends(get_db),
):
    """
    Получить рекомендации рецептов
    
    Включает рецепты из:
    1. Spoonacular API
    2. Каналов (популярные рецепты)
    
    Оптимизировано с кэшированием для быстрой загрузки.
    """
    # Если Spoonacular не настроен — отдаём рецепты из каналов/профилей, чтобы в Menu что-то было
    if not SPOONACULAR_API_KEY:
        try:
            channel_recipes = get_channel_recipes_for_recommendations(
                db, limit=limit, tags=tags, ingredients=ingredients
            )
            return {
                "recipes": channel_recipes[:limit],
                "meta": {
                    "mode": mode or "balanced",
                    "language": language or "ru",
                },
            }
        except Exception as e:
            logger.warning(f"Ошибка загрузки рецептов из каналов: {e}")
            return {
                "recipes": [],
                "meta": {"mode": mode or "balanced", "language": language or "ru"},
            }

    # Создаем ключ кэша
    cache_key = f"recommendations:{limit}:{tags or 'none'}:{language or 'ru'}"
    
    # Проверяем кэш
    try:
        cached = redis_client.get(cache_key)
        if cached:
            logger.info(f"✅ Используем кэш для рекомендаций: {cache_key}")
            return json.loads(cached)
    except (RedisConnectionError, RedisTimeoutError) as e:
        logger.warning(f"Redis недоступен для кэша: {e}")
    except Exception as e:
        logger.warning(f"Ошибка чтения кэша: {e}")
    
    url = "https://api.spoonacular.com/recipes/random"
    params = {
        "number": limit,
        "apiKey": SPOONACULAR_API_KEY,
    }
    
    if tags:
        params["tags"] = tags
    
    try:
        print(f"🌐 Запрос к Spoonacular: {url} с параметрами {params}")
        resp = requests.get(url, params=params, timeout=20)
        print(f"📡 Ответ Spoonacular: status={resp.status_code}")
        
        if resp.status_code != 200:
            print(f"❌ Ошибка Spoonacular: {resp.status_code} - {resp.text[:200]}")
            try:
                channel_recipes = get_channel_recipes_for_recommendations(
                    db, limit=limit, tags=tags, ingredients=ingredients
                )
                return {
                    "recipes": channel_recipes[:limit],
                    "meta": {"mode": mode or "balanced", "language": language or "ru"},
                }
            except Exception as e:
                logger.warning(f"Ошибка загрузки рецептов из каналов: {e}")
            return {
                "recipes": [],
                "meta": {"mode": mode or "balanced", "language": language or "ru"},
            }
        
        data = resp.json()
        print(f"📦 Ответ Spoonacular: keys={list(data.keys())}")
        recipes = data.get("recipes", [])
        print(f"📋 Получено {len(recipes)} рецептов из Spoonacular random API")
        
        if len(recipes) == 0:
            print(f"⚠️ ВНИМАНИЕ: Spoonacular вернул 0 рецептов!")
            print(f"   Структура ответа: {json.dumps(data, ensure_ascii=False)[:500]}")
        
        # Функция для параллельного получения калорий
        def fetch_calories(rid: int) -> dict:
            """Получает только калории для рецепта"""
            try:
                det_url = f"https://api.spoonacular.com/recipes/{rid}/information"
                dresp = requests.get(
                    det_url, 
                    params={
                        "apiKey": SPOONACULAR_API_KEY,
                        "includeNutrition": "true"
                    }, 
                    timeout=8  # Уменьшили timeout для скорости
                )
                if dresp.status_code == 200:
                    info = dresp.json()
                    nutrition_data = info.get("nutrition", {})
                    calories = None
                    protein = None
                    fat = None
                    carbs = None
                    
                    if nutrition_data:
                        nutrients = nutrition_data.get("nutrients", [])
                        if isinstance(nutrients, list):
                            for n in nutrients:
                                name = str(n.get("name", "")).lower()
                                title = str(n.get("title", "")).lower()
                                amount = n.get("amount")
                                unit = str(n.get("unit", "")).lower()
                                
                                # Используем title если name пустой
                                search_name = title if not name and title else name
                                
                                if amount is not None:
                                    if "calories" in search_name or "calorie" in search_name:
                                        calories = int(amount)
                                    elif "protein" in search_name:
                                        if protein is None:  # Берем первое найденное
                                            protein = float(amount)
                                    elif ("fat" in search_name and "total" in search_name) or search_name == "fat":
                                        if fat is None:  # Берем первое найденное
                                            fat = float(amount)
                                    elif ("carbohydrate" in search_name or "carbs" in search_name or "carb" in search_name) and "net" not in search_name:
                                        if carbs is None:  # Берем первое найденное
                                            carbs = float(amount)
                    
                    # Создаем упрощенный nutrition объект с БЖУ
                    simplified_nutrition = {}
                    if nutrition_data:
                        simplified_nutrition = nutrition_data.copy()
                    if protein is not None:
                        simplified_nutrition["protein"] = protein
                        simplified_nutrition["proteins"] = protein
                    if fat is not None:
                        simplified_nutrition["fat"] = fat
                        simplified_nutrition["fats"] = fat
                    if carbs is not None:
                        simplified_nutrition["carbs"] = carbs
                        simplified_nutrition["carbohydrates"] = carbs
                    
                    return {"calories": calories, "nutrition": simplified_nutrition}
            except Exception as e:
                print(f"⚠️ Error fetching calories for {rid}: {e}")
            return {"calories": None, "nutrition": None}
        
        # Используем данные из random endpoint (они уже полные!)
        out = []
        
        # Параллельно получаем калории для всех рецептов
        print(f"⚡ Параллельная загрузка калорий для {len(recipes)} рецептов...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            # Создаем задачи для параллельного выполнения
            future_to_recipe = {
                executor.submit(fetch_calories, rec.get("id")): rec 
                for rec in recipes
            }
            
            # Обрабатываем результаты по мере готовности
            for future in concurrent.futures.as_completed(future_to_recipe):
                rec = future_to_recipe[future]
                rid = rec.get("id")
                title = rec.get("title", "")
                image = rec.get("image", "") or ""
                
                # Получаем калории из параллельного запроса
                details = future.result()
                calories = details.get("calories")
                nutrition = details.get("nutrition")
                
                # Используем данные из random endpoint (они уже полные!)
                ingredients_list = [
                    i.get("original", "")
                    for i in rec.get("extendedIngredients", [])
                    if i.get("original")
                ]
                steps_list = parse_steps(rec)
                
                # Получаем язык из настроек
                user_settings = get_user_settings()
                target_lang = user_settings.get("language", language or "ru")
                
                # Переводим на язык пользователя
                translated_title = translate_text(title, target_lang)
                translated_ingredients = translate_list(ingredients_list, target_lang)
                translated_steps = translate_steps(steps_list, target_lang)
                
                # Очищаем пустые строки для изображений
                image_clean = image.strip() if image else None
                if not image_clean or image_clean == "":
                    image_clean = None
                
                item = {
                    "id": rid,
                    "title": title,
                    "image": image_clean,
                    "source_image": image_clean,
                    "ingredients": ingredients_list,
                    "steps": steps_list,
                    "usedIngredientCount": rec.get("usedIngredientCount", len(ingredients_list)),
                    "instructions_raw": strip_html_tags(rec.get("instructions") or ""),
                    "translated_title": translated_title,
                    "translated_ingredients": translated_ingredients,
                    "translated_steps": translated_steps,
                    "calories": calories,
                    "nutrition": nutrition,
                }
                out.append(item)
        
        print(f"⚡ Параллельная загрузка завершена: {len(out)} рецептов")
        
        # Добавляем рецепты из каналов
        try:
            channel_recipes = get_channel_recipes_for_recommendations(
                db, 
                limit=min(limit // 2, 5), 
                tags=tags,
                ingredients=ingredients
            )
            # Объединяем: сначала рецепты из каналов (более актуальные), потом из API
            all_recipes = channel_recipes + out[:max(limit - len(channel_recipes), 0)]
        except Exception as e:
            print(f"⚠️ Error fetching channel recipes: {e}")
            all_recipes = out
        
        print(f"📤 Возвращаем {len(all_recipes)} рецептов (из них {len(channel_recipes) if 'channel_recipes' in locals() else 0} из каналов)")
        result = {
            "recipes": all_recipes[:limit],  # Ограничиваем общим лимитом
            "meta": {
                "mode": mode or "balanced",
                "language": language or "ru",
            }
        }
        
        # Сохраняем в кэш на 1 час (3600 секунд)
        try:
            redis_client.setex(cache_key, 3600, json.dumps(result, ensure_ascii=False, default=str))
            logger.info(f"💾 Сохранено в кэш: {cache_key}")
        except (RedisConnectionError, RedisTimeoutError) as e:
            logger.warning(f"Redis недоступен для сохранения кэша: {e}")
        except Exception as e:
            logger.warning(f"Ошибка сохранения кэша: {e}")
        
        return result
    except Exception as e:
        print(f"Error fetching recommendations: {e}")
        try:
            channel_recipes = get_channel_recipes_for_recommendations(
                db, limit=limit, tags=tags, ingredients=ingredients
            )
            return {
                "recipes": channel_recipes[:limit],
                "meta": {
                    "mode": mode or "balanced",
                    "language": language or "ru",
                },
            }
        except Exception as e2:
            logger.warning(f"Fallback channel recipes failed: {e2}")
        return {
            "recipes": [],
            "meta": {
                "mode": mode or "balanced",
                "language": language or "ru",
            },
        }


@router.post("/recipes")
async def search_recipes(
    ingredients: str = Body(..., description="Ингредиенты для поиска"),
    mode: Optional[str] = Body(None, description="Режим анализа"),
    language: Optional[str] = Body(None, description="Язык"),
    tags: Optional[str] = Body(None, description="Теги для фильтрации"),
    max_ready_time: Optional[int] = Body(None, description="Макс. время готовки в минутах (фильтр)"),
    db: Session = Depends(get_db),
):
    """
    Поиск рецептов по ингредиентам
    """
    if not ingredients or not ingredients.strip():
        return {"recipes": [], "meta": {}}
    
    if not SPOONACULAR_API_KEY:
        return {"recipes": [], "meta": {}}
    
    # Получаем настройки
    user_settings = get_user_settings()
    requested_mode = normalize_mode(mode or user_settings.get("analysis_mode", DEFAULT_MODE))
    lang = (language or user_settings.get("language", DEFAULT_LANGUAGE)).lower()
    
    # Проверяем кэш в Redis
    cache_key = f"recipes:{ingredients.lower()}:{requested_mode}:{lang}:{max_ready_time or 0}"
    try:
        cached = redis_client.get(cache_key)
        if cached:
            data = json.loads(cached)
            # Сохраняем в историю
            store_history_entry(ingredients, None, requested_mode)
            return {"recipes": data, "meta": {"mode": requested_mode, "language": lang}}
    except Exception as e:
        # Redis недоступен, продолжаем без кэша
        print(f"Redis cache error (continuing without cache): {e}")
    
    # Определяем, является ли запрос списком ингредиентов или названием блюда
    # Если есть запятые, это скорее всего список ингредиентов
    # Если нет запятых, это скорее всего название блюда
    is_ingredient_list = ',' in ingredients or ' и ' in ingredients.lower()
    
    # Используем complexSearch для поиска по названию/описанию и ингредиентам
    # Это позволяет искать и "макароны с мясом", и "яйца, мука, молоко"
    search_url = "https://api.spoonacular.com/recipes/complexSearch"
    params = {
        "query": ingredients,  # Поиск по названию, описанию и ингредиентам
        "number": 12,  # Увеличиваем количество для лучших результатов
        "addRecipeInformation": "true",  # Получаем полную информацию сразу
        "fillIngredients": "true",  # Заполняем ингредиенты
        "instructionsRequired": "true",  # Только рецепты с инструкциями
        "apiKey": SPOONACULAR_API_KEY,
    }
    if tags:
        params["tags"] = tags
    if max_ready_time is not None and max_ready_time > 0:
        params["maxReadyTime"] = max_ready_time
    
    # Если это список ингредиентов, также пробуем findByIngredients для лучших результатов
    list_recipes = []
    try:
        # Основной поиск через complexSearch
        print(f"🔍 Запрос к complexSearch: query='{ingredients}', tags={tags}")
        resp = requests.get(search_url, params=params, timeout=30)
        print(f"🔍 complexSearch ответ: status={resp.status_code}")
        if resp.status_code == 200:
            data = resp.json()
            list_recipes = data.get("results", []) or []
            print(f"🔍 complexSearch нашел {len(list_recipes)} рецептов")
            if list_recipes:
                print(f"🔍 Первый рецепт: {list_recipes[0].get('title', 'N/A')}")
            else:
                print(f"⚠️ complexSearch вернул пустой результат. Ответ API: {json.dumps(data)[:500]}")
        elif resp.status_code != 200:
            print(f"⚠️ complexSearch вернул ошибку {resp.status_code}: {resp.text[:200]}")
            # Если complexSearch вернул ошибку, сразу пробуем findByIngredients
            list_recipes = []
        
        # Если complexSearch не вернул результатов, пробуем findByIngredients
        # Это работает и для названий блюд, так как Spoonacular может найти рецепты по ключевым словам
        if len(list_recipes) == 0:
            print(f"🔍 complexSearch не вернул результатов, пробуем findByIngredients...")
            ingredients_url = "https://api.spoonacular.com/recipes/findByIngredients"
            # Для названий блюд извлекаем ключевые ингредиенты (например, "макароны с мясом" -> "макароны, мясо")
            search_ingredients = ingredients
            if not is_ingredient_list:
                # Пробуем извлечь ключевые слова из запроса
                # Простая логика: разбиваем по пробелам и убираем предлоги
                words = [w.strip() for w in ingredients.split() if w.strip() and w.strip().lower() not in ['с', 'и', 'в', 'на', 'для', 'из']]
                search_ingredients = ', '.join(words[:5])  # Берем первые 5 слов
                print(f"🔍 Извлеченные ингредиенты из запроса: '{search_ingredients}'")
            
            ingredients_params = {
                "ingredients": search_ingredients,
                "number": 12,
                "apiKey": SPOONACULAR_API_KEY,
            }
            if tags:
                ingredients_params["tags"] = tags
            
            try:
                ingredients_resp = requests.get(ingredients_url, params=ingredients_params, timeout=30)
                print(f"🔍 findByIngredients ответ: status={ingredients_resp.status_code}")
                if ingredients_resp.status_code == 200:
                    ingredients_recipes = ingredients_resp.json() or []
                    print(f"🔍 findByIngredients нашел {len(ingredients_recipes)} рецептов")
                    # Объединяем результаты, избегая дубликатов
                    existing_ids = {r.get("id") for r in list_recipes}
                    for item in ingredients_recipes:
                        if item.get("id") not in existing_ids:
                            list_recipes.append(item)
                            existing_ids.add(item.get("id"))
                    print(f"🔍 Всего рецептов после объединения: {len(list_recipes)}")
                else:
                    print(f"⚠️ findByIngredients вернул ошибку {ingredients_resp.status_code}: {ingredients_resp.text[:200]}")
            except Exception as e:
                print(f"⚠️ Ошибка при запросе findByIngredients: {e}")
        
        if not list_recipes:
            return {"recipes": [], "meta": {"mode": requested_mode, "language": lang}}
        
        # Функция для параллельного получения детальной информации
        def fetch_recipe_info(rid: int, item: dict) -> dict:
            """Получает детальную информацию о рецепте"""
            try:
                # Если complexSearch уже вернул полную информацию (addRecipeInformation=true), используем её
                if item.get("extendedIngredients") is not None or item.get("analyzedInstructions") is not None:
                    # Данные уже есть в item от complexSearch
                    ext = item.get("extendedIngredients", []) or []
                    ingredients_list = []
                    for i in ext:
                        if isinstance(i, dict):
                            original = i.get("original", "")
                            if original:
                                ingredients_list.append(original.strip())
                        else:
                            ingredients_list.append(str(i).strip())
                    
                    steps = parse_steps(item) if item.get("analyzedInstructions") else []
                    image = item.get("image", "") or ""
                    
                    # Получаем калории и БЖУ из item
                    nutrition_data = item.get("nutrition", {})
                    calories = None
                    protein = None
                    fat = None
                    carbs = None
                    
                    if nutrition_data:
                        nutrients = nutrition_data.get("nutrients", [])
                        if isinstance(nutrients, list):
                            for n in nutrients:
                                name = str(n.get("name", "")).lower()
                                title = str(n.get("title", "")).lower()
                                amount = n.get("amount")
                                search_name = title if not name and title else name
                                
                                if amount is not None:
                                    if "calories" in search_name or "calorie" in search_name:
                                        calories = int(amount)
                                    elif "protein" in search_name:
                                        if protein is None:
                                            protein = float(amount)
                                    elif ("fat" in search_name and "total" in search_name) or search_name == "fat":
                                        if fat is None:
                                            fat = float(amount)
                                    elif ("carbohydrate" in search_name or "carbs" in search_name or "carb" in search_name) and "net" not in search_name:
                                        if carbs is None:
                                            carbs = float(amount)
                    
                    # Создаем упрощенный nutrition объект с БЖУ
                    simplified_nutrition = {}
                    if nutrition_data:
                        simplified_nutrition = nutrition_data.copy()
                    if protein is not None:
                        simplified_nutrition["protein"] = protein
                        simplified_nutrition["proteins"] = protein
                    if fat is not None:
                        simplified_nutrition["fat"] = fat
                        simplified_nutrition["fats"] = fat
                    if carbs is not None:
                        simplified_nutrition["carbs"] = carbs
                        simplified_nutrition["carbohydrates"] = carbs
                    
                    return {
                        "ingredients": ingredients_list,
                        "steps": steps,
                        "image": image,
                        "calories": calories,
                        "nutrition": simplified_nutrition
                    }
                
                # Если данных нет, запрашиваем детальную информацию
                det_url = f"https://api.spoonacular.com/recipes/{rid}/information"
                dresp = requests.get(
                    det_url, 
                    params={
                        "apiKey": SPOONACULAR_API_KEY,
                        "includeNutrition": "true"
                    }, 
                    timeout=8
                )
                if dresp.status_code == 200:
                    info = dresp.json()
                    ext = info.get("extendedIngredients", []) or []
                    ingredients_list = [
                        i.get("original", "").strip() for i in ext if i.get("original")
                    ]
                    steps = parse_steps(info)
                    image = info.get("image", "") or item.get("image", "")
                    
                    # Получаем калории и БЖУ
                    nutrition_data = info.get("nutrition", {})
                    calories = None
                    protein = None
                    fat = None
                    carbs = None
                    
                    if nutrition_data:
                        nutrients = nutrition_data.get("nutrients", [])
                        if isinstance(nutrients, list):
                            for n in nutrients:
                                name = str(n.get("name", "")).lower()
                                title = str(n.get("title", "")).lower()
                                amount = n.get("amount")
                                search_name = title if not name and title else name
                                
                                if amount is not None:
                                    if "calories" in search_name or "calorie" in search_name:
                                        calories = int(amount)
                                    elif "protein" in search_name:
                                        if protein is None:
                                            protein = float(amount)
                                    elif ("fat" in search_name and "total" in search_name) or search_name == "fat":
                                        if fat is None:
                                            fat = float(amount)
                                    elif ("carbohydrate" in search_name or "carbs" in search_name or "carb" in search_name) and "net" not in search_name:
                                        if carbs is None:
                                            carbs = float(amount)
                    
                    # Создаем упрощенный nutrition объект с БЖУ
                    simplified_nutrition = {}
                    if nutrition_data:
                        simplified_nutrition = nutrition_data.copy()
                    if protein is not None:
                        simplified_nutrition["protein"] = protein
                        simplified_nutrition["proteins"] = protein
                    if fat is not None:
                        simplified_nutrition["fat"] = fat
                        simplified_nutrition["fats"] = fat
                    if carbs is not None:
                        simplified_nutrition["carbs"] = carbs
                        simplified_nutrition["carbohydrates"] = carbs
                    
                    return {
                        "ingredients": ingredients_list,
                        "steps": steps,
                        "image": image,
                        "calories": calories,
                        "nutrition": simplified_nutrition
                    }
            except Exception as e:
                print(f"⚠️ Error fetching info for {rid}: {e}")
            return {
                "ingredients": [],
                "steps": [],
                "image": item.get("image", ""),
                "calories": None,
                "nutrition": None
            }
        
        # Параллельно получаем информацию для всех рецептов
        print(f"⚡ Параллельная загрузка деталей для {len(list_recipes)} рецептов...")
        out = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_item = {
                executor.submit(fetch_recipe_info, item.get("id"), item): item 
                for item in list_recipes
            }
            
            for future in concurrent.futures.as_completed(future_to_item):
                item = future_to_item[future]
                rid = item.get("id")
                title = item.get("title", "")
                info = future.result()
                
                # Очищаем пустые строки для изображений
                image_clean = info["image"].strip() if info["image"] else None
                if not image_clean or image_clean == "":
                    image_clean = None
                
                # Получаем язык из настроек пользователя
                user_settings = get_user_settings()
                target_lang = user_settings.get("language", lang or "ru")
                
                # Переводим на язык пользователя
                translated_title = translate_text(title, target_lang)
                translated_ingredients = translate_list(info["ingredients"], target_lang)
                translated_steps = translate_steps(info["steps"], target_lang)
                
                # Определяем usedIngredientCount
                used_ingredient_count = item.get("usedIngredientCount", 0)
                if used_ingredient_count == 0 and info["ingredients"]:
                    # Если usedIngredientCount не указан, используем количество ингредиентов
                    used_ingredient_count = len(info["ingredients"])
                
                # Получаем количество лайков и добавлений в план питания из базы данных
                # Для рецептов Spoonacular, которые не были сохранены пользователями, значения будут 0
                likes_count = 0
                meal_plan_count = 0
                try:
                    from app.models.like import Like
                    from sqlalchemy import func
                    
                    # Ищем посты, связанные с этим рецептом Spoonacular
                    # Проверяем body как JSON, где может быть recipe_id или id
                    posts = db.query(Post).filter(
                        Post.type == "recipe",
                        Post.status == "published",
                        Post.deleted_at.is_(None)
                    ).all()
                    
                    # Ищем пост, где body содержит ID рецепта Spoonacular
                    for post in posts:
                        if post.body and isinstance(post.body, dict):
                            # Проверяем различные варианты хранения ID рецепта
                            recipe_id_in_post = (
                                post.body.get("recipe_id") == rid or
                                post.body.get("id") == rid or
                                post.body.get("spoonacular_id") == rid or
                                str(post.body.get("recipe_id")) == str(rid) or
                                str(post.body.get("id")) == str(rid)
                            )
                            
                            if recipe_id_in_post:
                                # Считаем лайки для этого поста
                                likes_count = db.query(func.count(Like.id)).filter(
                                    Like.post_id == post.id
                                ).scalar() or 0
                                break
                    
                    # Считаем добавления в план питания по ID рецепта Spoonacular
                    # Используем raw SQL для подсчета из таблицы meal_plan_entries
                    try:
                        from sqlalchemy import text
                        result = db.execute(
                            text("SELECT COUNT(*) FROM meal_plan_entries WHERE recipe_id = :rid OR recipe_id = CAST(:rid AS TEXT)"),
                            {"rid": str(rid)}
                        ).scalar()
                        meal_plan_count = result or 0
                    except Exception as e:
                        # Если таблица не найдена или произошла ошибка, используем 0
                        print(f"⚠️ Не удалось получить meal_plan_count для рецепта {rid}: {e}")
                        meal_plan_count = 0
                except Exception as e:
                    print(f"⚠️ Ошибка при получении статистики для рецепта {rid}: {e}")
                
                recipe_payload = {
                    "id": rid,
                    "title": title,
                    "image": image_clean,
                    "source_image": image_clean,
                    "usedIngredientCount": used_ingredient_count,
                    "ingredients": info["ingredients"],
                    "steps": info["steps"],
                    "instructions_raw": item.get("instructions", "") or "",
                    "translated_title": translated_title,
                    "translated_ingredients": translated_ingredients,
                    "translated_steps": translated_steps,
                    "calories": info["calories"],
                    "nutrition": info["nutrition"],
                    "likes_count": likes_count,
                    "meal_plan_count": meal_plan_count,
                }
                out.append(recipe_payload)
        
        print(f"⚡ Параллельная загрузка завершена: {len(out)} рецептов")
        
        # Сохраняем в кэш
        try:
            redis_client.setex(cache_key, CACHE_TTL, json.dumps(out, ensure_ascii=False))
        except Exception as e:
            print(f"Redis cache save error (continuing without cache): {e}")
        
        # ГИБРИДНЫЙ ПОДХОД: базовая база → пользовательские → Spoonacular
        all_recipes = []
        
        # 1. Сначала ищем в базовой базе (только для русского языка)
        if lang == "ru":
            base_recipes = search_base_recipes(ingredients, db, limit=8)
            all_recipes.extend(base_recipes)
            print(f"📚 Найдено {len(base_recipes)} рецептов из базовой базы")
        
        # 2. Если не хватает, добавляем рецепты пользователей
        if len(all_recipes) < 8:
            user_recipes = search_user_recipes(ingredients, db, limit=8 - len(all_recipes))
            all_recipes.extend(user_recipes)
            print(f"👥 Найдено {len(user_recipes)} рецептов пользователей")
        
        # 3. Если все еще не хватает, дополняем из Spoonacular (с оптимизированным переводом)
        if len(all_recipes) < 8:
            remaining = 8 - len(all_recipes)
            # Ограничиваем результаты Spoonacular до нужного количества
            spoonacular_recipes = out[:remaining]
            all_recipes.extend(spoonacular_recipes)
            print(f"🌐 Добавлено {len(spoonacular_recipes)} рецептов из Spoonacular")
        else:
            # Если уже достаточно из базовой базы и пользовательских, не используем Spoonacular
            print(f"✅ Достаточно рецептов из базовой базы и пользовательских, Spoonacular не используется")
        
        # Сортируем по релевантности: сначала базовая база (relevance_score), потом по usedIngredientCount
        all_recipes.sort(key=lambda x: (
            x.get("relevance_score", 0) if "base" in str(x.get("id", "")) else 0,
            x.get("usedIngredientCount", 0)
        ), reverse=True)
        
        # Ограничиваем результат до 8 рецептов
        all_recipes = all_recipes[:8]
        
        # Сохраняем в историю
        store_history_entry(ingredients, None, requested_mode)
        
        return {"recipes": all_recipes, "meta": {"mode": requested_mode, "language": lang}}
    except Exception as e:
        print(f"Error searching recipes: {e}")
        # В случае ошибки все равно пытаемся вернуть рецепты из каналов и профилей
        try:
            channel_recipes = search_user_recipes(ingredients, db, limit=10)
            return {"recipes": channel_recipes, "meta": {"mode": requested_mode, "language": lang}}
        except Exception as e:
            print(f"⚠️ Error fetching user recipes: {e}")
            return {"recipes": [], "meta": {"mode": requested_mode, "language": lang}}


@router.get("/recipes/{recipe_id}")
async def get_recipe_by_id(
    recipe_id: int,
    language: Optional[str] = Query(None, description="Язык перевода (ru, en, ...)"),
    db: Session = Depends(get_db),
):
    """
    Получить один рецепт по ID (для открытия по ссылке из шаринга).
    Поддерживаются ID рецептов Spoonacular.
    """
    if not SPOONACULAR_API_KEY:
        raise HTTPException(status_code=502, detail="Spoonacular API key not configured")
    user_settings = get_user_settings()
    lang = (language or user_settings.get("language", DEFAULT_LANGUAGE)).lower()
    det_url = f"https://api.spoonacular.com/recipes/{recipe_id}/information"
    try:
        resp = requests.get(
            det_url,
            params={"apiKey": SPOONACULAR_API_KEY, "includeNutrition": "true"},
            timeout=10,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=404, detail="Recipe not found")
        info = resp.json()
    except requests.RequestException as e:
        logger.warning(f"get_recipe_by_id request error: {e}")
        raise HTTPException(status_code=502, detail="Failed to fetch recipe")
    title = info.get("title", "")
    ext = info.get("extendedIngredients", []) or []
    ingredients_list = [i.get("original", "").strip() for i in ext if i.get("original")]
    steps = parse_steps(info)
    image = (info.get("image", "") or "").strip() or None
    nutrition_data = info.get("nutrition", {})
    calories = None
    protein = fat = carbs = None
    if nutrition_data and isinstance(nutrition_data.get("nutrients"), list):
        for n in nutrition_data["nutrients"]:
            name = str(n.get("name", "")).lower()
            amount = n.get("amount")
            if amount is None:
                continue
            if "calorie" in name:
                calories = int(amount)
            elif "protein" in name:
                protein = float(amount)
            elif name == "fat" or "fat" in name:
                fat = float(amount)
            elif "carbohydrate" in name or "carb" in name:
                carbs = float(amount)
    simplified_nutrition = {}
    if protein is not None:
        simplified_nutrition["protein"] = protein
    if fat is not None:
        simplified_nutrition["fat"] = fat
    if carbs is not None:
        simplified_nutrition["carbohydrates"] = carbs
    translated_title = translate_text(title, lang)
    translated_ingredients = translate_list(ingredients_list, lang)
    translated_steps = translate_steps(steps, lang)
    likes_count = 0
    meal_plan_count = 0
    try:
        from app.models.like import Like
        from sqlalchemy import func, text
        posts = db.query(Post).filter(
            Post.type == "recipe",
            Post.status == "published",
            Post.deleted_at.is_(None),
        ).all()
        for post in posts:
            if post.body and isinstance(post.body, dict):
                rid_ok = (
                    post.body.get("recipe_id") == recipe_id
                    or post.body.get("id") == recipe_id
                    or str(post.body.get("recipe_id")) == str(recipe_id)
                )
                if rid_ok:
                    likes_count = db.query(func.count(Like.id)).filter(Like.post_id == post.id).scalar() or 0
                    break
        result = db.execute(
            text("SELECT COUNT(*) FROM meal_plan_entries WHERE recipe_id = :rid OR recipe_id = CAST(:rid AS TEXT)"),
            {"rid": str(recipe_id)},
        )
        meal_plan_count = result.scalar() or 0
    except Exception as e:
        logger.warning(f"get_recipe_by_id stats: {e}")
    return {
        "id": recipe_id,
        "title": title,
        "image": image,
        "source_image": image,
        "usedIngredientCount": len(ingredients_list),
        "ingredients": ingredients_list,
        "steps": steps,
        "translated_title": translated_title,
        "translated_ingredients": translated_ingredients,
        "translated_steps": translated_steps,
        "calories": calories,
        "nutrition": simplified_nutrition,
        "likes_count": likes_count,
        "meal_plan_count": meal_plan_count,
        "source": "spoonacular",
    }


@router.post("/analyze")
async def analyze_photo(
    image_base64: Optional[str] = Body(None, description="Изображение в base64"),
    image_url: Optional[str] = Body(None, description="URL изображения"),
    mode: Optional[str] = Body(None, description="Режим анализа"),
    language: Optional[str] = Body(None, description="Язык"),
):
    """
    Анализ фото еды
    """
    if not image_base64 and not image_url:
        raise HTTPException(status_code=400, detail="image_base64 or image_url required")
    
    if not SPOONACULAR_API_KEY:
        raise HTTPException(status_code=502, detail="Spoonacular API key not configured")
    
    user_settings = get_user_settings()
    lang = (language or user_settings.get("language", DEFAULT_LANGUAGE)).lower()
    requested_mode = normalize_mode(mode or user_settings.get("analysis_mode", DEFAULT_MODE))
    
    raw = None
    url = "https://api.spoonacular.com/food/images/analyze"
    
    try:
        if image_base64:
            try:
                cleaned = image_base64.split(",")[-1]
                image_bytes = base64.b64decode(cleaned)
            except Exception as exc:
                raise HTTPException(status_code=400, detail=f"invalid base64 payload: {exc}")
            
            files = {
                "file": ("capture.jpg", image_bytes, "image/jpeg"),
            }
            resp = requests.post(
                url,
                params={"apiKey": SPOONACULAR_API_KEY},
                files=files,
                timeout=40,
            )
            if resp.status_code == 200:
                raw = resp.json()
        else:
            resp = requests.post(
                url,
                params={"apiKey": SPOONACULAR_API_KEY},
                data={"imageUrl": image_url},
                timeout=40,
            )
            if resp.status_code == 200:
                raw = resp.json()
        
        if not raw:
            raise HTTPException(status_code=502, detail="analysis failed")
        
        nutrition = raw.get("nutrition", {}) or {}
        nutrients = nutrition.get("nutrients") or (nutrition.get("nutrition") or {}).get("nutrients", [])
        calories = None
        simplified_nutrition = {}
        name_to_key = {
            "calories": "calories",
            "protein": "protein",
            "fat": "fat",
            "carbohydrates": "carbohydrates",
            "carbohydrate": "carbohydrates",
            "carbs": "carbohydrates",
            "fiber": "fiber",
            "sugar": "sugar",
            "sodium": "sodium",
        }

        def _parse_amount(v):
            if v is None:
                return None
            if isinstance(v, (int, float)):
                return v
            if isinstance(v, str):
                import re
                v = re.sub(r"\s*(g|mg|kcal|ккал|г|мг)\s*$", "", v.strip(), flags=re.IGNORECASE)
                try:
                    return float(v)
                except ValueError:
                    return None
            return None

        if isinstance(nutrients, list):
            for n in nutrients:
                name = (n.get("name") or "").strip().lower()
                amount = _parse_amount(n.get("amount"))
                if name == "calories" and amount is not None:
                    calories = amount
                if amount is not None and name:
                    key = name_to_key.get(name) or name.replace(" ", "_")
                    if key != "calories" and key not in simplified_nutrition:
                        simplified_nutrition[key] = amount

        if not simplified_nutrition and isinstance(nutrition, dict):
            for key in ("protein", "fat", "carbohydrates", "carbs", "carbohydrate", "fiber", "sugar", "sodium"):
                val = nutrition.get(key) or nutrition.get(key.capitalize())
                if val is not None:
                    parsed = _parse_amount(val)
                    if parsed is not None:
                        norm_key = "carbohydrates" if key in ("carbs", "carbohydrate") else key
                        if norm_key not in simplified_nutrition:
                            simplified_nutrition[norm_key] = parsed
            if calories is None:
                cal_val = nutrition.get("calories") or nutrition.get("Calories")
                calories = _parse_amount(cal_val)

        confidence = raw.get("confidence")
        category = raw.get("category", {}) or {}
        category_name = (category.get("name") or "").strip()
        if category_name and lang != "en":
            try:
                translated_category = translate_text(category_name, lang)
                if translated_category:
                    category_name = translated_category
            except Exception as e:
                print(f"⚠️ Failed to translate category name: {e}")
        
        recipes_raw = raw.get("recipes", []) or []
        recipes = []
        for rec in recipes_raw:
            image = rec.get("image")
            orig_title = (rec.get("title") or "").strip()
            translated_title_val = orig_title
            if orig_title and lang != "en":
                try:
                    translated_title_val = translate_text(orig_title, lang) or orig_title
                except Exception as e:
                    print(f"⚠️ Failed to translate recipe title: {e}")
            recipes.append({
                "id": rec.get("id"),
                "title": orig_title,
                "translated_title": translated_title_val,
                "image": build_proxy(image) if image else None,
                "source_image": image,
                "source": "spoonacular",
                "ingredients": [],
                "steps": [],
                "usedIngredientCount": 0,
                "confidence": rec.get("confidence"),
            })
        
        analysis = {
            "label": category.get("name"),
            "translated_label": category_name or category.get("name"),
            "confidence": confidence,
            "nutrition": simplified_nutrition,
            "calories": calories,
            "recipes": recipes,
        }
        
        return {"analysis": analysis, "mode": requested_mode, "language": lang}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error analyzing photo: {e}")
        raise HTTPException(status_code=502, detail=f"analysis failed: {str(e)}")


@router.get("/settings")
async def get_settings():
    """Получить настройки пользователя"""
    return get_user_settings()


@router.post("/settings")
async def update_settings(
    analysis_mode: Optional[str] = Body(None, description="Режим анализа"),
    language: Optional[str] = Body(None, description="Язык"),
):
    """Обновить настройки пользователя"""
    current = get_user_settings()
    new_mode = normalize_mode(analysis_mode or current.get("analysis_mode", DEFAULT_MODE))
    new_language = (language or current.get("language") or DEFAULT_LANGUAGE).lower()
    new_settings = {"analysis_mode": new_mode, "language": new_language}
    save_user_settings(new_settings)
    return new_settings


@router.get("/favorites")
async def get_favorites():
    """Получить избранные рецепты"""
    try:
        favorites_json = redis_client.get("favorites") or "{}"
        favorites = json.loads(favorites_json)
        favs = list(favorites.values())
        # Сортируем по времени добавления (если есть ts)
        favs.sort(key=lambda x: x.get("ts", 0), reverse=True)
        return {"favorites": favs}
    except Exception as e:
        print(f"Error getting favorites: {e}")
        return {"favorites": []}


@router.post("/favorites")
async def add_favorite(body: Dict[str, Any] = Body(..., description="Тело запроса")):
    """Добавить рецепт в избранное"""
    # Поддерживаем два формата: прямой рецепт или {"recipe": {...}}
    recipe = body.get("recipe") if "recipe" in body else body
    
    if not isinstance(recipe, dict):
        print(f"⚠️ Recipe is not a dict: {type(recipe)}")
        raise HTTPException(status_code=400, detail="recipe must be a dictionary")
    
    rid = recipe.get("id")
    if rid is None:
        print(f"⚠️ Recipe has no id. Keys: {list(recipe.keys())}")
        raise HTTPException(status_code=400, detail="recipe has no id")
    
    # Убеждаемся, что ID - это число
    if not isinstance(rid, (int, float)):
        try:
            rid = int(rid)
            recipe["id"] = rid  # Обновляем ID в рецепте
        except (ValueError, TypeError):
            print(f"⚠️ Recipe id is not a number: {rid} (type: {type(rid)})")
            raise HTTPException(status_code=400, detail=f"recipe id must be a number, got: {type(rid).__name__}")
    
    try:
        favorites_json = redis_client.get("favorites") or "{}"
        favorites = json.loads(favorites_json)
        recipe["ts"] = int(time.time())
        favorites[str(rid)] = recipe
        redis_client.set("favorites", json.dumps(favorites, ensure_ascii=False))
        return {"ok": True}
    except Exception as e:
        print(f"Error adding favorite: {e}")
        raise HTTPException(status_code=500, detail="failed to add favorite")


@router.delete("/favorites/{rid}")
async def remove_favorite(rid: int):
    """Удалить рецепт из избранного"""
    try:
        favorites_json = redis_client.get("favorites") or "{}"
        favorites = json.loads(favorites_json)
        if str(rid) in favorites:
            del favorites[str(rid)]
            redis_client.set("favorites", json.dumps(favorites, ensure_ascii=False))
        return {"ok": True}
    except Exception as e:
        print(f"Error removing favorite: {e}")
        raise HTTPException(status_code=500, detail="failed to remove favorite")


@router.get("/history")
async def get_history(limit: int = Query(25, ge=1, le=100)):
    """Получить историю поиска"""
    try:
        history_json = redis_client.get("search_history") or "[]"
        history = json.loads(history_json)
        # Сортируем по времени и ограничиваем
        history = sorted(history, key=lambda x: x.get("ts", 0), reverse=True)[:limit]
        return {"history": history}
    except Exception as e:
        print(f"Error getting history: {e}")
        return {"history": []}


@router.delete("/history")
async def clear_history():
    """Очистить историю поиска"""
    try:
        redis_client.delete("search_history")
        return {"ok": True}
    except Exception as e:
        print(f"Error clearing history: {e}")
        raise HTTPException(status_code=500, detail="failed to clear history")


@router.get("/recipes/{recipe_id}/comments")
async def get_recipe_comments(recipe_id: int):
    """Получить комментарии к рецепту"""
    try:
        comments_key = f"recipe_comments:{recipe_id}"
        comments_json = redis_client.get(comments_key) or "[]"
        comments = json.loads(comments_json)
        # Сортируем по времени создания (новые первыми)
        comments.sort(key=lambda x: x.get("created_at", 0), reverse=True)
        return {"comments": comments}
    except Exception as e:
        print(f"Error getting recipe comments: {e}")
        return {"comments": []}


@router.get("/recipes/image-proxy")
async def proxy_recipe_image(url: str = Query(..., description="URL изображения для проксирования")):
    """
    Прокси для изображений рецептов (решает проблему CORS в Flutter Web)
    """
    try:
        # Декодируем URL если он закодирован
        import urllib.parse
        if url.startswith("http"):
            image_url = url
        else:
            image_url = urllib.parse.unquote(url)
        
        # Проверяем, что это URL от Spoonacular
        if not image_url.startswith("https://img.spoonacular.com") and not image_url.startswith("https://spoonacular.com"):
            raise HTTPException(status_code=400, detail="Invalid image URL")
        
        # Загружаем изображение
        resp = requests.get(
            image_url, 
            timeout=10, 
            stream=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            }
        )
        if resp.status_code != 200:
            print(f"❌ Image proxy error: {resp.status_code} for {image_url[:80]}...")
            raise HTTPException(status_code=resp.status_code, detail="Failed to fetch image")
        
        # Определяем content type
        content_type = resp.headers.get("Content-Type", "image/jpeg")
        
        # Возвращаем изображение с правильными CORS заголовками
        return Response(
            content=resp.content,
            media_type=content_type,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "*",
                "Cache-Control": "public, max-age=86400",  # Кэш на 24 часа
            }
        )
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching image: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


@router.post("/recipes/{recipe_id}/comments")
async def add_recipe_comment(
    recipe_id: int,
    author: Optional[str] = Body(None, description="Автор комментария"),
    text: str = Body(..., description="Текст комментария"),
    author_avatar: Optional[str] = Body(None, description="Аватар автора"),
    author_id: Optional[str] = Body(None, description="ID автора для проверки прав"),
    rating: Optional[int] = Body(None, ge=1, le=5, description="Рейтинг от 1 до 5"),
):
    """Добавить комментарий к рецепту"""
    if not text or not text.strip():
        raise HTTPException(status_code=400, detail="Text is required")
    
    try:
        comments_key = f"recipe_comments:{recipe_id}"
        
        # Пытаемся получить комментарии из Redis
        try:
            comments_json = redis_client.get(comments_key) or "[]"
            comments = json.loads(comments_json)
        except (RedisConnectionError, RedisTimeoutError) as redis_error:
            # Если Redis недоступен, начинаем с пустого списка
            logger.warning(f"Redis недоступен при получении комментариев: {redis_error}")
            comments = []
        except Exception as e:
            logger.error(f"Ошибка при чтении комментариев из Redis: {e}")
            comments = []
        
        # Создаем новый комментарий
        # ID должен быть int, но используем timestamp для уникальности
        comment_id = int(time.time() * 1000)
        new_comment = {
            "id": comment_id,
            "recipe_id": str(recipe_id),  # Фронтенд ожидает String
            "author": author or "Anonymous",
            "author_id": author_id,  # ID автора для проверки прав удаления
            "author_avatar": author_avatar,
            "text": text.strip(),
            "rating": rating,  # Рейтинг от 1 до 5
            "created_at": int(time.time()),
        }
        
        comments.append(new_comment)
        
        # Пытаемся сохранить обратно в Redis
        try:
            redis_client.set(comments_key, json.dumps(comments, ensure_ascii=False))
        except (RedisConnectionError, RedisTimeoutError) as redis_error:
            # Если Redis недоступен, просто логируем предупреждение
            logger.warning(f"Redis недоступен при сохранении комментария: {redis_error}. Комментарий будет потерян при перезапуске.")
        except Exception as e:
            logger.error(f"Ошибка при сохранении комментария в Redis: {e}")
        
        # Обновляем средний рейтинг рецепта
        if rating:
            try:
                _update_recipe_rating(recipe_id)
            except Exception as e:
                logger.warning(f"Не удалось обновить рейтинг рецепта: {e}")
        
        return {"ok": True, "comment": new_comment}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error adding recipe comment: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to add comment: {str(e)}")


def _update_recipe_rating(recipe_id: int):
    """Обновляет средний рейтинг рецепта на основе комментариев"""
    try:
        comments_key = f"recipe_comments:{recipe_id}"
        comments_json = redis_client.get(comments_key) or "[]"
        comments = json.loads(comments_json)
        
        # Вычисляем средний рейтинг
        ratings = [c.get("rating") for c in comments if c.get("rating")]
        if ratings:
            avg_rating = sum(ratings) / len(ratings)
            # Сохраняем средний рейтинг
            rating_key = f"recipe_rating:{recipe_id}"
            redis_client.set(rating_key, json.dumps({
                "rating": round(avg_rating, 1),
                "count": len(ratings),
                "updated_at": int(time.time())
            }, ensure_ascii=False))
    except Exception as e:
        print(f"Error updating recipe rating: {e}")


@router.delete("/recipes/{recipe_id}/comments/{comment_id}")
async def delete_recipe_comment(
    recipe_id: int,
    comment_id: int,
    author_id: Optional[str] = Query(None, description="ID автора для проверки прав"),
):
    """Удалить комментарий к рецепту (только автор может удалить)"""
    try:
        comments_key = f"recipe_comments:{recipe_id}"
        comments_json = redis_client.get(comments_key) or "[]"
        comments = json.loads(comments_json)
        
        # Находим комментарий
        comment_index = None
        for i, comment in enumerate(comments):
            if comment.get("id") == comment_id:
                comment_index = i
                break
        
        if comment_index is None:
            raise HTTPException(status_code=404, detail="Comment not found")
        
        comment = comments[comment_index]
        
        # Проверяем права: только автор может удалить
        if author_id and comment.get("author_id") != author_id:
            raise HTTPException(status_code=403, detail="You can only delete your own comments")
        
        # Удаляем комментарий
        comments.pop(comment_index)
        
        # Сохраняем обратно в Redis
        redis_client.set(comments_key, json.dumps(comments, ensure_ascii=False))
        
        # Обновляем средний рейтинг
        _update_recipe_rating(recipe_id)
        
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting recipe comment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to delete comment: {str(e)}")


@router.get("/recipes/{recipe_id}/rating")
async def get_recipe_rating(recipe_id: int):
    """Получить средний рейтинг рецепта"""
    try:
        rating_key = f"recipe_rating:{recipe_id}"
        rating_json = redis_client.get(rating_key)
        if rating_json:
            return json.loads(rating_json)
        return {"rating": 0.0, "count": 0}
    except Exception as e:
        print(f"Error getting recipe rating: {e}")
        return {"rating": 0.0, "count": 0}
