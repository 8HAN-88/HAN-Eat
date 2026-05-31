"""
API для работы с рецептами и рекомендациями
"""
from fastapi import APIRouter, Query, HTTPException, Body, Depends, status
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
import re
from sqlalchemy.orm import Session
from redis.exceptions import ConnectionError as RedisConnectionError, TimeoutError as RedisTimeoutError
from app.core.config import settings
from app.core.redis_client import get_redis, redis_client
from app.core.database import get_db
from app.models.post import Post
from app.models.community import Channel
from app.models.base_recipe import BaseRecipe
from app.models.user import User
from app.api.dependencies import get_current_user, get_current_user_required
from app.services.analytics_service import AnalyticsService

logger = logging.getLogger(__name__)

# Попытка импортировать библиотеку для перевода
TRANSLATOR_AVAILABLE = False
GoogleTranslator = None
Translator = None

try:
    from deep_translator import GoogleTranslator
    TRANSLATOR_AVAILABLE = True
    logger.info("deep-translator доступен для переводов")
except ImportError:
    try:
        from googletrans import Translator
        TRANSLATOR_AVAILABLE = True
        Translator = Translator()
        logger.info("googletrans доступен для переводов")
    except (ImportError, AttributeError) as e:
        logger.warning("Переводчик не установлен: %s", e)
        TRANSLATOR_AVAILABLE = False

router = APIRouter()

# Получаем API ключ Spoonacular из настроек
SPOONACULAR_API_KEY = settings.SPOONACULAR_API_KEY


def _inject_viewer_plus_meta(
    meta: Optional[Dict[str, Any]], db: Session, current_user: Optional[User]
) -> None:
    """Поля для клиента: Plus у зрителя и подсказка обновить подписку при исчерпании квоты Spoonacular."""
    if not isinstance(meta, dict):
        return
    from app.services.subscription_service import SubscriptionService

    svc = SubscriptionService(db)
    is_plus = bool(current_user and svc.is_user_plus(current_user.id))
    meta["viewer_is_plus"] = is_plus
    meta["suggest_plus_upgrade"] = bool(meta.get("spoonacular_quota_exhausted")) and not is_plus


def _nested_author_from_body(body: dict) -> tuple:
    """Имя/аватар из вложенного body['author'] (как в некоторых клиентах)."""
    nested = body.get("author")
    if not isinstance(nested, dict):
        return (None, None)
    raw_name = nested.get("name") or nested.get("display_name")
    name = raw_name.strip() if isinstance(raw_name, str) and raw_name.strip() else None
    raw_av = nested.get("avatar_url") or nested.get("avatarUrl")
    avatar = raw_av.strip() if isinstance(raw_av, str) and raw_av.strip() else None
    return (name, avatar)


def _recipe_author_fields(db: Session, post: Post) -> tuple:
    """
    Имя и аватар для карточки меню: канал (avatar_url канала) или автор поста на стене (avatar пользователя).
    """
    body = post.body if isinstance(post.body, dict) else {}
    if post.channel_id:
        ch = db.query(Channel).filter(Channel.id == post.channel_id).first()
        if ch:
            avatar = (ch.avatar_url or ch.cover_url or "").strip() or None
            name = (ch.name or "").strip() or None
            # Fallback из тела поста (старые клиенты)
            if not name:
                raw = body.get("channel_name") or body.get("community_name") or body.get("group_name")
                name = raw.strip() if isinstance(raw, str) and raw.strip() else None
            if not avatar:
                av = (
                    body.get("channel_avatar")
                    or body.get("channel_image_url")
                    or body.get("group_avatar")
                )
                if isinstance(av, str) and av.strip():
                    avatar = av.strip()
            # Аватар админа канала, если у канала нет своей картинки
            if not avatar and ch.admin_user_id:
                admin = db.query(User).filter(User.id == ch.admin_user_id).first()
                if admin and admin.avatar_url:
                    avatar = (admin.avatar_url or "").strip() or None
            # Рецепт в канале: аватар автора поста (часто единственное фото в профиле)
            if not avatar and post.user_id:
                author_user = db.query(User).filter(User.id == post.user_id).first()
                if author_user and author_user.avatar_url:
                    avatar = (author_user.avatar_url or "").strip() or None
            nb_name, nb_avatar = _nested_author_from_body(body)
            if not name and nb_name:
                name = nb_name
            if not avatar and nb_avatar:
                avatar = nb_avatar
            return (name, avatar)
        # Канал мог быть удален/недоступен: фолбэк к автору поста
    user = db.query(User).filter(User.id == post.user_id).first()
    if user:
        label = (user.name or user.username or user.email or "").strip() or None
        avatar = (user.avatar_url or "").strip() or None
        if not label:
            for key in ("author_name", "display_name", "user_name", "username", "group_name"):
                v = body.get(key)
                if isinstance(v, str) and v.strip():
                    label = v.strip()
                    break
        if not avatar:
            for key in (
                "author_avatar",
                "user_avatar",
                "avatar_url",
                "profile_image_url",
                "group_avatar",
            ):
                v = body.get(key)
                if isinstance(v, str) and v.strip():
                    avatar = v.strip()
                    break
        nb_name, nb_avatar = _nested_author_from_body(body)
        if not label and nb_name:
            label = nb_name
        if not avatar and nb_avatar:
            avatar = nb_avatar
        return (label, avatar)
    return (None, None)

# Константы
CACHE_TTL = 12 * 3600  # 12 hours cache
DEFAULT_LANGUAGE = "ru"
DEFAULT_MODE = "all"
ALLOWED_MODES = {"recipe", "calories", "all"}
MAX_HISTORY_ENTRIES = 50


def _calories_and_nutrition_from_random_recipe(rec: dict) -> tuple:
    """Калории из ответа /recipes/random (если есть nutrition), без второго API-запроса."""
    nutrition = rec.get("nutrition")
    if not isinstance(nutrition, dict):
        return None, None
    nutrients = nutrition.get("nutrients")
    if not isinstance(nutrients, list):
        return None, nutrition
    calories = None
    for n in nutrients:
        if not isinstance(n, dict):
            continue
        name = str(n.get("name", "")).lower()
        if "calorie" in name and n.get("amount") is not None:
            try:
                calories = int(float(n["amount"]))
            except (TypeError, ValueError):
                calories = None
            break
    return calories, nutrition


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
        logger.warning(f"⚠️ Redis translation cache read error: {e}")
    return None


def cache_translation(text: str, target_lang: str, translated: str):
    """Сохранить перевод в кеш Redis"""
    if not text or not translated or target_lang == "en":
        return
    
    try:
        cache_key = f"translation:{hashlib.md5(f'{text}:{target_lang}'.encode()).hexdigest()}"
        redis_client.setex(cache_key, 86400 * 30, translated)  # 30 дней
    except Exception as e:
        logger.warning(f"⚠️ Redis translation cache write error: {e}")


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
                logger.warning(f"⚠️ Translation connection error (attempt {attempt + 1}/{max_retries}), retrying in {wait_time:.1f}s...")
                time.sleep(wait_time)
                continue
            else:
                # Если это не ошибка соединения или последняя попытка, просто логируем
                if attempt == max_retries - 1:
                    logger.warning(f"⚠️ Translation error for '{text[:30]}...' (after {max_retries} attempts): {e}")
                else:
                    logger.warning(f"⚠️ Translation error for '{text[:30]}...' (attempt {attempt + 1}/{max_retries}): {e}")
    
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


def translate_query_to_english_for_spoonacular(q: str) -> Optional[str]:
    """
    Spoonacular complexSearch по кириллице часто возвращает 0 результатов.
    Короткий запрос (название блюда) переводим на английский для повторного поиска.
    """
    s = (q or "").strip()
    if len(s) < 2:
        return None
    if not any(ord(c) > 127 for c in s):
        return None
    if not TRANSLATOR_AVAILABLE or GoogleTranslator is None:
        return None
    try:
        translator = GoogleTranslator(source="auto", target="en")
        out = translator.translate(s)
        out = (out or "").strip()
        if not out or out.lower() == s.lower():
            return None
        return out
    except Exception as e:
        logger.warning("translate_query_to_english_for_spoonacular failed: %s", e)
        return None


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


def _meal_plan_count_for_recipe_id(db: Session, rid: str) -> int:
    """Сколько раз рецепт с данным внешним id встречается в meal_plan_entries (если таблицы нет — 0)."""
    try:
        from sqlalchemy import text

        result = db.execute(
            text(
                "SELECT COUNT(*) FROM meal_plan_entries "
                "WHERE recipe_id = :rid OR recipe_id = CAST(:rid AS TEXT)"
            ),
            {"rid": str(rid)},
        ).scalar()
        return int(result or 0)
    except Exception:
        return 0


def _likes_count_for_external_recipe_id(db: Session, rid: object) -> int:
    """Лайки поста type=recipe, в body которого указан тот же внешний id (base_*, Spoonacular и т.д.)."""
    from app.models.like import Like
    from sqlalchemy import func

    rid_str = str(rid)
    posts = (
        db.query(Post)
        .filter(
            Post.type == "recipe",
            Post.status == "published",
            Post.deleted_at.is_(None),
        )
        .all()
    )
    for post in posts:
        body = post.body
        if not body or not isinstance(body, dict):
            continue
        for key in ("recipe_id", "id", "spoonacular_id", "base_recipe_id"):
            val = body.get(key)
            if val is None:
                continue
            if val == rid or str(val) == rid_str:
                return db.query(func.count(Like.id)).filter(Like.post_id == post.id).scalar() or 0
    return 0


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
        matched_count = 0
        title_lower = (recipe.title or "").lower()
        for word in query_words:
            if word in title_lower:
                matched_count += 2
        card = _base_recipe_to_card(recipe, db, relevance_score=matched_count)
        recipes.append(card)
    
    # Сортируем по релевантности
    recipes.sort(key=lambda x: x.get("relevance_score", 0), reverse=True)
    
    return recipes


def _base_recipe_to_card(
    recipe: BaseRecipe, db: Session, *, relevance_score: int = 0
) -> Dict[str, Any]:
    ingredients = recipe.ingredients or []
    formatted_ingredients: List[str] = []
    for ing in ingredients:
        if isinstance(ing, str):
            formatted_ingredients.append(ing)
        elif isinstance(ing, dict):
            formatted_ingredients.append(ing.get("name", "") or str(ing))

    steps = recipe.steps or []
    formatted_steps: List[Dict[str, Any]] = []
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

    rid = f"base_{recipe.id}"
    return {
        "id": rid,
        "title": recipe.title,
        "image": recipe.image_url,
        "source_image": recipe.image_url,
        "ingredients": formatted_ingredients,
        "steps": formatted_steps,
        "usedIngredientCount": len(formatted_ingredients),
        "translated_title": recipe.title,
        "translated_ingredients": formatted_ingredients,
        "translated_steps": formatted_steps,
        "calories": recipe.calories,
        "nutrition": recipe.nutrition or {},
        "likes_count": _likes_count_for_external_recipe_id(db, rid),
        "meal_plan_count": _meal_plan_count_for_recipe_id(db, rid),
        "source": "base",
        "relevance_score": relevance_score,
    }


def list_popular_base_recipes(db: Session, limit: int = 8) -> List[Dict[str, Any]]:
    """Популярные рецепты из локальной базы (без Spoonacular)."""
    results = (
        db.query(BaseRecipe)
        .order_by(BaseRecipe.popularity_score.desc(), BaseRecipe.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_base_recipe_to_card(r, db) for r in results]


def _nutrition_from_recipe_body(body: Dict[str, Any]) -> tuple:
    nutrition = body.get("nutrition")
    if isinstance(nutrition, dict) and nutrition:
        return body.get("calories"), nutrition
    protein = body.get("protein_g")
    carbs = body.get("carbs_g")
    fat = body.get("fat_g")
    if protein is None and carbs is None and fat is None:
        return body.get("calories"), None
    built = {}
    if protein is not None:
        built["protein"] = protein
    if carbs is not None:
        built["carbohydrates"] = carbs
    if fat is not None:
        built["fat"] = fat
    return body.get("calories"), built or None


def _merge_recipe_cards(*lists: List[Dict[str, Any]], limit: int) -> List[Dict[str, Any]]:
    seen: set = set()
    out: List[Dict[str, Any]] = []
    for lst in lists:
        for card in lst:
            rid = card.get("id")
            if rid in seen:
                continue
            seen.add(rid)
            out.append(card)
            if len(out) >= limit:
                return out
    return out


def get_recommendations_local_fallback(
    db: Session,
    limit: int,
    tags: Optional[str] = None,
    ingredients: Optional[str] = None,
    *,
    apply_spoonacular_tag_filter: bool = False,
) -> List[Dict[str, Any]]:
    """Каналы/профили + база рецептов, когда Spoonacular недоступен."""
    channel_tags = tags if apply_spoonacular_tag_filter else None
    channel = get_channel_recipes_for_recommendations(
        db, limit=limit, tags=channel_tags, ingredients=ingredients
    )
    base = list_popular_base_recipes(db, limit=limit)
    return _merge_recipe_cards(channel, base, limit=limit)


def _recommendations_cache_usable(payload: Dict[str, Any]) -> bool:
    recipes = payload.get("recipes") or []
    meta = payload.get("meta") or {}
    if len(recipes) < 3:
        return False
    if meta.get("spoonacular_quota_exhausted"):
        return False
    return True


def _recommendations_response(
    recipes: List[Dict[str, Any]],
    meta: Optional[Dict[str, Any]],
    db: Session,
    current_user: Optional[User],
    language: Optional[str],
) -> Dict[str, Any]:
    """Ответ /recommendations: перевод карточек для AI-подписчиков (после общего кэша)."""
    from app.services.recipe_localization_service import apply_recipe_localization_to_cards

    lang = (language or "ru").lower()
    localized, loc_meta = apply_recipe_localization_to_cards(
        recipes, lang, db, current_user, full=False
    )
    merged_meta = dict(meta or {})
    merged_meta.update(loc_meta)
    _inject_viewer_plus_meta(merged_meta, db, current_user)
    return {"recipes": localized, "meta": merged_meta}


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
    # Короткие токены в сериализованном JSON дают массу ложных совпадений (подстроки в ключах/числах).
    # Для SQL-фильтра по body используем только токены не короче 3 символов; скоринг ниже — по всем терминам.
    _min_sql_token = 3
    sql_terms = [t for t in all_search_terms if len(t) >= _min_sql_token]
    if not sql_terms:
        sql_terms = list(all_search_terms)
    if not sql_terms:
        return []

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
        Post.is_global_visible.is_(True),
    ).group_by(Post.id)
    
    # Фильтруем по тексту запроса (без cast(body) целиком — он ловит мусор в JSON/URL).
    search_filters = []
    for term in sql_terms:
        search_filters.append(func.lower(Post.title).contains(term))
        if Post.description:
            search_filters.append(func.lower(Post.description).contains(term))
        # Только ингредиенты и шаги в body, не весь JSON
        search_filters.append(
            func.lower(
                func.coalesce(func.cast(Post.body["ingredients"], String), "")
            ).contains(term)
        )
        search_filters.append(
            func.lower(
                func.coalesce(func.cast(Post.body["steps"], String), "")
            ).contains(term)
        )
        if Post.tags:
            search_filters.append(
                func.lower(func.coalesce(func.cast(Post.tags, String), "")).contains(term)
            )
    
    if search_filters:
        query = query.filter(or_(*search_filters))
    
    # Сортируем по релевантности (matched_count будет добавлен позже), лайкам и дате
    # Пока сортируем по лайкам и дате, релевантность добавим в цикле
    results = query.order_by(
        func.count(Like.id).desc(),
        Post.published_at.desc()
    ).limit(limit * 2).all()  # Берем больше, чтобы потом отсортировать по релевантности
    
    recipes_with_relevance = []
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
            if term in (post.title or "").lower():
                matched_count += 2
            if post.description and term in post.description.lower():
                matched_count += 1
            if post.tags:
                for tag in post.tags:
                    if tag and term in str(tag).lower():
                        matched_count += 2
                        break
            for post_ing in formatted_ingredients:
                if term in post_ing.lower():
                    matched_count += 1
                    break
            for step in body.get("steps", []) or []:
                step_text = (
                    step.get("text", step.get("step", ""))
                    if isinstance(step, dict)
                    else str(step)
                )
                if step_text and term in step_text.lower():
                    matched_count += 1
                    break

        # SQL мог совпасть по шуму в JSON; без совпадения по смыслу в выдачу не попадаем
        if matched_count < 1:
            continue

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
        
        author, author_avatar = _recipe_author_fields(db, post)

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
            "author": author,
            "author_avatar": author_avatar,
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
    from sqlalchemy import func, or_, String
    
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
        Post.is_global_visible.is_(True),
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
                func.lower(func.cast(Post.body, String)).contains(ing)
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
        author, author_avatar = _recipe_author_fields(db, post)

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
        
        calories, nutrition = _nutrition_from_recipe_body(body)
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
            "calories": calories,
            "nutrition": nutrition,
            "channel_id": post.channel_id,
            "user_id": post.user_id,
            "source": "user" if post.channel_id is None else "channel",
            "likes_count": likes_count or 0,
            "author": author,
            "author_avatar": author_avatar,
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
    quick: bool = Query(
        True,
        description="Быстрый ответ: без N+1 запросов за калориями и без онлайн-перевода (меню)",
    ),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user),
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
            local_recipes = get_recommendations_local_fallback(
                db, limit=limit, tags=tags, ingredients=ingredients
            )
            meta = {
                "mode": mode or "balanced",
                "language": language or "ru",
            }
            return _recommendations_response(
                local_recipes[:limit], meta, db, current_user, language
            )
        except Exception as e:
            logger.warning(f"Ошибка загрузки рецептов из каналов: {e}")
            meta = {"mode": mode or "balanced", "language": language or "ru"}
            return _recommendations_response([], meta, db, current_user, language)

    # Ключ кэша: при изменении состава полей (например author/author_avatar) — поднять версию.
    cache_key = f"recommendations:v9:{limit}:{tags or 'none'}:{language or 'ru'}:q{int(quick)}"
    
    # Проверяем кэш
    try:
        cached = redis_client.get(cache_key)
        if cached:
            payload = json.loads(cached)
            if _recommendations_cache_usable(payload):
                logger.info(f"✅ Используем кэш для рекомендаций: {cache_key}")
                return _recommendations_response(
                    payload.get("recipes") or [],
                    payload.get("meta"),
                    db,
                    current_user,
                    language,
                )
            logger.info(
                "Пропуск кэша рекомендаций (%s): мало карточек или исчерпана квота Spoonacular",
                cache_key,
            )
    except (RedisConnectionError, RedisTimeoutError) as e:
        logger.warning(f"Redis недоступен для кэша: {e}")
    except Exception as e:
        logger.warning(f"Ошибка чтения кэша: {e}")
    
    url = "https://api.spoonacular.com/recipes/random"
    params = {
        "number": limit,
        "apiKey": SPOONACULAR_API_KEY,
    }
    # Одним ответом больше данных: ингредиенты/шаги/калории без N+1
    if quick:
        params["includeNutrition"] = "true"
        params["addRecipeInformation"] = "true"
        params["fillIngredients"] = "true"
    
    if tags:
        params["tags"] = tags
    
    try:
        logger.debug(f"🌐 Запрос к Spoonacular: {url} с параметрами {params}")
        resp = requests.get(url, params=params, timeout=20)
        logger.debug(f"📡 Ответ Spoonacular: status={resp.status_code}")
        
        if resp.status_code != 200:
            logger.warning(f"❌ Ошибка Spoonacular: {resp.status_code} - {resp.text[:200]}")
            quota_exhausted = resp.status_code == 402 or (
                "points limit" in (resp.text or "").lower()
                or "daily points" in (resp.text or "").lower()
            )
            meta_err = {
                "mode": mode or "balanced",
                "language": language or "ru",
                "spoonacular_status": resp.status_code,
                "spoonacular_quota_exhausted": quota_exhausted,
            }
            try:
                local_recipes = get_recommendations_local_fallback(
                    db,
                    limit=limit,
                    tags=tags,
                    ingredients=ingredients,
                    apply_spoonacular_tag_filter=False,
                )
                return _recommendations_response(
                    local_recipes[:limit], meta_err, db, current_user, language
                )
            except Exception as e:
                logger.warning(f"Ошибка локального fallback рекомендаций: {e}")
            return _recommendations_response([], meta_err, db, current_user, language)
        
        data = resp.json()
        logger.debug(f"📦 Ответ Spoonacular: keys={list(data.keys())}")
        recipes = data.get("recipes", [])
        logger.debug(f"📋 Получено {len(recipes)} рецептов из Spoonacular random API")
        
        if len(recipes) == 0:
            logger.warning(f"⚠️ ВНИМАНИЕ: Spoonacular вернул 0 рецептов!")
            logger.debug(f"   Структура ответа: {json.dumps(data, ensure_ascii=False)[:500]}")
        
        # Быстрый режим: один ответ Spoonacular, без перевода и без N+1 — иначе меню не успевает загрузиться
        if quick:
            logger.debug(f"⚡ Режим quick=1: {len(recipes)} рецептов без перевода и без доп. запросов за калориями")
            out_quick: List[dict] = []
            for rec in recipes:
                rid = rec.get("id")
                title = rec.get("title", "")
                image = rec.get("image", "") or ""
                ingredients_list = [
                    i.get("original", "")
                    for i in rec.get("extendedIngredients", [])
                    if i.get("original")
                ]
                steps_list = parse_steps(rec)
                calories, nutrition = _calories_and_nutrition_from_random_recipe(rec)
                image_clean = image.strip() if image else None
                if not image_clean:
                    image_clean = None
                else:
                    image_clean = _spoonacular_card_image_url(image_clean)
                out_quick.append(
                    {
                        "id": rid,
                        "title": title,
                        "image": image_clean,
                        "source_image": image_clean,
                        "ingredients": ingredients_list,
                        "steps": steps_list,
                        "usedIngredientCount": rec.get("usedIngredientCount", len(ingredients_list)),
                        "instructions_raw": strip_html_tags(rec.get("instructions") or ""),
                        "translated_title": title,
                        "translated_ingredients": ingredients_list,
                        "translated_steps": [
                            {
                                "number": s.get("number", i + 1),
                                "step": s.get("step", ""),
                                "instruction": s.get("instruction", s.get("step", "")),
                                "image": s.get("image"),
                            }
                            for i, s in enumerate(steps_list)
                        ],
                        "calories": calories,
                        "nutrition": nutrition,
                        "source": "spoonacular",
                    }
                )
            out = out_quick
            logger.debug(f"⚡ Quick: собрано {len(out)} рецептов")
        if not quick:
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
                        timeout=8,
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
                                    title_n = str(n.get("title", "")).lower()
                                    amount = n.get("amount")

                                    search_name = title_n if not name and title_n else name

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
                    logger.warning(f"⚠️ Error fetching calories for {rid}: {e}")
                return {"calories": None, "nutrition": None}

            out = []
            logger.debug(f"⚡ Параллельная загрузка калорий для {len(recipes)} рецептов...")
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
                future_to_recipe = {
                    executor.submit(fetch_calories, rec.get("id")): rec
                    for rec in recipes
                }

                for future in concurrent.futures.as_completed(future_to_recipe):
                    rec = future_to_recipe[future]
                    rid = rec.get("id")
                    title = rec.get("title", "")
                    image = rec.get("image", "") or ""

                    details = future.result()
                    calories = details.get("calories")
                    nutrition = details.get("nutrition")

                    ingredients_list = [
                        i.get("original", "")
                        for i in rec.get("extendedIngredients", [])
                        if i.get("original")
                    ]
                    steps_list = parse_steps(rec)

                    user_settings = get_user_settings()
                    target_lang = user_settings.get("language", language or "ru")

                    translated_title = translate_text(title, target_lang)
                    translated_ingredients = translate_list(ingredients_list, target_lang)
                    translated_steps = translate_steps(steps_list, target_lang)

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
                        "source": "spoonacular",
                    }
                    out.append(item)

            logger.debug(f"⚡ Параллельная загрузка завершена: {len(out)} рецептов")
        
        # Добавляем рецепты из каналов (до полного лимита), затем дополняем Spoonacular
        try:
            channel_recipes = get_channel_recipes_for_recommendations(
                db,
                limit=limit,
                tags=tags,
                ingredients=ingredients
            )
            # Объединяем: сначала рецепты из каналов (более актуальные), потом из API
            all_recipes = channel_recipes + out[:max(limit - len(channel_recipes), 0)]
        except Exception as e:
            logger.warning(f"⚠️ Error fetching channel recipes: {e}")
            all_recipes = out

        if len(all_recipes) < limit:
            base_extra = list_popular_base_recipes(db, limit=limit)
            all_recipes = _merge_recipe_cards(all_recipes, base_extra, limit=limit)
        
        logger.debug(f"📤 Возвращаем {len(all_recipes)} рецептов (из них {len(channel_recipes) if 'channel_recipes' in locals() else 0} из каналов)")
        result = {
            "recipes": all_recipes[:limit],  # Ограничиваем общим лимитом
            "meta": {
                "mode": mode or "balanced",
                "language": language or "ru",
            },
        }
        
        # Сохраняем в кэш на 1 час — не кэшируем «бедные» ответы при исчерпании квоты
        if _recommendations_cache_usable(result):
            try:
                redis_client.setex(
                    cache_key, 3600, json.dumps(result, ensure_ascii=False, default=str)
                )
                logger.info(f"💾 Сохранено в кэш: {cache_key}")
            except (RedisConnectionError, RedisTimeoutError) as e:
                logger.warning(f"Redis недоступен для сохранения кэша: {e}")
            except Exception as e:
                logger.warning(f"Ошибка сохранения кэша: {e}")
        
        return _recommendations_response(
            result.get("recipes") or [],
            result.get("meta"),
            db,
            current_user,
            language,
        )
    except Exception as e:
        logger.warning(f"Error fetching recommendations: {e}")
        try:
            local_recipes = get_recommendations_local_fallback(
                db,
                limit=limit,
                tags=tags,
                ingredients=ingredients,
                apply_spoonacular_tag_filter=False,
            )
            meta = {
                "mode": mode or "balanced",
                "language": language or "ru",
            }
            return _recommendations_response(
                local_recipes[:limit], meta, db, current_user, language
            )
        except Exception as e2:
            logger.warning(f"Fallback channel recipes failed: {e2}")
        meta = {
            "mode": mode or "balanced",
            "language": language or "ru",
        }
        return _recommendations_response([], meta, db, current_user, language)


@router.post("/recipes")
async def search_recipes(
    ingredients: str = Body(..., description="Ингредиенты для поиска"),
    mode: Optional[str] = Body(None, description="Режим анализа"),
    language: Optional[str] = Body(None, description="Язык"),
    tags: Optional[str] = Body(None, description="Теги для фильтрации"),
    max_ready_time: Optional[int] = Body(None, description="Макс. время готовки в минутах (фильтр)"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user),
):
    """
    Поиск рецептов по ингредиентам
    """
    if not ingredients or not ingredients.strip():
        return {"recipes": [], "meta": {}}
    
    # Получаем настройки
    user_settings = get_user_settings()
    requested_mode = normalize_mode(mode or user_settings.get("analysis_mode", DEFAULT_MODE))
    lang = (language or user_settings.get("language", DEFAULT_LANGUAGE)).lower()

    from app.services.recipe_localization_service import (
        apply_recipe_localization_to_cards,
        card_needs_localization,
        viewer_can_localize_recipes,
    )

    can_localize = viewer_can_localize_recipes(db, current_user, lang)
    
    # Проверяем кэш в Redis
    cache_key = f"recipes:v3:{ingredients.lower()}:{requested_mode}:{lang}:{max_ready_time or 0}"
    try:
        cached = redis_client.get(cache_key)
        if cached:
            data = json.loads(cached)
            store_history_entry(ingredients, None, requested_mode)
            meta_cached: Dict[str, Any] = {"mode": requested_mode, "language": lang}
            if can_localize:
                data, loc = apply_recipe_localization_to_cards(
                    data, lang, db, current_user, full=True
                )
                meta_cached.update(loc)
            elif any(card_needs_localization(c, lang) for c in data):
                meta_cached["recipe_translation_requires_ai"] = True
            return {"recipes": data, "meta": meta_cached}
    except Exception as e:
        # Redis недоступен, продолжаем без кэша
        logger.warning("Redis cache error (continuing without cache): %s", e)
    
    # Определяем, является ли запрос списком ингредиентов или названием блюда
    # Если есть запятые, это скорее всего список ингредиентов
    # Если нет запятых, это скорее всего название блюда
    is_ingredient_list = ',' in ingredients or ' и ' in ingredients.lower()

    # Spoonacular (если ключ задан). Без ключа или при пустом ответе ниже подмешиваются база + каналы/профили.
    list_recipes: List[Dict[str, Any]] = []
    if SPOONACULAR_API_KEY:
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

        try:
            # Основной поиск через complexSearch
            logger.debug(f"🔍 Запрос к complexSearch: query='{ingredients}', tags={tags}")
            resp = requests.get(search_url, params=params, timeout=30)
            logger.debug(f"🔍 complexSearch ответ: status={resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                list_recipes = data.get("results", []) or []
                logger.debug(f"🔍 complexSearch нашел {len(list_recipes)} рецептов")
                if list_recipes:
                    logger.debug(f"🔍 Первый рецепт: {list_recipes[0].get('title', 'N/A')}")
                else:
                    logger.warning(f"⚠️ complexSearch вернул пустой результат. Ответ API: {json.dumps(data)[:500]}")
            elif resp.status_code != 200:
                logger.warning(f"⚠️ complexSearch вернул ошибку {resp.status_code}: {resp.text[:200]}")
                list_recipes = []

            # Повтор complexSearch с английским запросом (кириллица в query часто даёт 0 результатов)
            if len(list_recipes) == 0:
                en_query = translate_query_to_english_for_spoonacular(ingredients)
                if en_query:
                    params_en = dict(params)
                    params_en["query"] = en_query
                    logger.debug("🔁 complexSearch (EN fallback): query=%r", en_query)
                    try:
                        resp_en = requests.get(search_url, params=params_en, timeout=30)
                        if resp_en.status_code == 200:
                            data_en = resp_en.json()
                            list_recipes = data_en.get("results", []) or []
                            logger.debug(
                                "🔁 EN complexSearch: %s рецептов", len(list_recipes)
                            )
                        else:
                            logger.warning(
                                "⚠️ EN complexSearch HTTP %s: %s",
                                resp_en.status_code,
                                (resp_en.text or "")[:200],
                            )
                    except Exception as ex:
                        logger.warning("⚠️ EN complexSearch request failed: %s", ex)

            # Если complexSearch не вернул результатов, пробуем findByIngredients
            if len(list_recipes) == 0:
                logger.debug(f"🔍 complexSearch не вернул результатов, пробуем findByIngredients...")
                ingredients_url = "https://api.spoonacular.com/recipes/findByIngredients"
                search_ingredients = ingredients
                if not is_ingredient_list:
                    words = [w.strip() for w in ingredients.split() if w.strip() and w.strip().lower() not in ['с', 'и', 'в', 'на', 'для', 'из']]
                    search_ingredients = ', '.join(words[:5])
                    logger.debug(f"🔍 Извлеченные ингредиенты из запроса: '{search_ingredients}'")

                ingredients_params = {
                    "ingredients": search_ingredients,
                    "number": 12,
                    "apiKey": SPOONACULAR_API_KEY,
                }
                if tags:
                    ingredients_params["tags"] = tags

                try:
                    ingredients_resp = requests.get(ingredients_url, params=ingredients_params, timeout=30)
                    logger.debug(f"🔍 findByIngredients ответ: status={ingredients_resp.status_code}")
                    if ingredients_resp.status_code == 200:
                        ingredients_recipes = ingredients_resp.json() or []
                        logger.debug(f"🔍 findByIngredients нашел {len(ingredients_recipes)} рецептов")
                        existing_ids = {r.get("id") for r in list_recipes}
                        for item in ingredients_recipes:
                            if item.get("id") not in existing_ids:
                                list_recipes.append(item)
                                existing_ids.add(item.get("id"))
                        logger.debug(f"🔍 Всего рецептов после объединения: {len(list_recipes)}")
                    else:
                        logger.warning(f"⚠️ findByIngredients вернул ошибку {ingredients_resp.status_code}: {ingredients_resp.text[:200]}")
                except Exception as e:
                    logger.warning(f"⚠️ Ошибка при запросе findByIngredients: {e}")
        except Exception as e:
            logger.warning("⚠️ Ошибка запросов Spoonacular: %s", e)
            list_recipes = []
    else:
        logger.info("SPOONACULAR_API_KEY не задан — поиск только по базе и постам каналов/профиля")

    if not list_recipes:
        logger.debug(
            "Spoonacular не дал рецептов — собираем ответ из базы и постов каналов/профиля"
        )
    
    try:
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
                logger.warning(f"⚠️ Error fetching info for {rid}: {e}")
            return {
                "ingredients": [],
                "steps": [],
                "image": item.get("image", ""),
                "calories": None,
                "nutrition": None
            }
    
        # Параллельно получаем информацию для всех рецептов
        logger.debug(f"⚡ Параллельная загрузка деталей для {len(list_recipes)} рецептов...")
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
            
                user_settings = get_user_settings()
                target_lang = user_settings.get("language", lang or "ru")

                if can_localize:
                    translated_title = translate_text(title, target_lang)
                    translated_ingredients = translate_list(
                        info["ingredients"], target_lang
                    )
                    translated_steps = translate_steps(info["steps"], target_lang)
                else:
                    translated_title = title
                    translated_ingredients = info["ingredients"]
                    translated_steps = info["steps"]
            
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

                    posts = db.query(Post).filter(
                        Post.type == "recipe",
                        Post.status == "published",
                        Post.deleted_at.is_(None)
                    ).all()

                    for post in posts:
                        if post.body and isinstance(post.body, dict):
                            recipe_id_in_post = (
                                post.body.get("recipe_id") == rid or
                                post.body.get("id") == rid or
                                post.body.get("spoonacular_id") == rid or
                                str(post.body.get("recipe_id")) == str(rid) or
                                str(post.body.get("id")) == str(rid)
                            )

                            if recipe_id_in_post:
                                likes_count = db.query(func.count(Like.id)).filter(
                                    Like.post_id == post.id
                                ).scalar() or 0
                                break

                    meal_plan_count = _meal_plan_count_for_recipe_id(db, str(rid))
                except Exception as e:
                    logger.warning(f"⚠️ Ошибка при получении статистики для рецепта {rid}: {e}")
            
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
                    "source": "spoonacular",
                }
                out.append(recipe_payload)

        # as_completed() перемешивает порядок — для complexSearch важен порядок релевантности API
        _order = {item.get("id"): i for i, item in enumerate(list_recipes)}
        out.sort(key=lambda r: _order.get(r.get("id"), 10**9))
    
        logger.debug(f"⚡ Параллельная загрузка завершена: {len(out)} рецептов")
    
        # ГИБРИДНЫЙ ПОДХОД: базовая база → пользовательские → Spoonacular
        all_recipes = []
    
        # 1. Сначала ищем в базовой базе (только для русского языка)
        if lang == "ru":
            base_recipes = search_base_recipes(ingredients, db, limit=8)
            all_recipes.extend(base_recipes)
            logger.debug(f"📚 Найдено {len(base_recipes)} рецептов из базовой базы")
    
        # 2. Если не хватает, добавляем рецепты пользователей
        if len(all_recipes) < 8:
            user_recipes = search_user_recipes(ingredients, db, limit=8 - len(all_recipes))
            all_recipes.extend(user_recipes)
            logger.debug(f"👥 Найдено {len(user_recipes)} рецептов пользователей")
    
        # 3. Если все еще не хватает, дополняем из Spoonacular (с оптимизированным переводом)
        if len(all_recipes) < 8:
            remaining = 8 - len(all_recipes)
            # Ограничиваем результаты Spoonacular до нужного количества
            spoonacular_recipes = out[:remaining]
            all_recipes.extend(spoonacular_recipes)
            logger.debug(f"🌐 Добавлено {len(spoonacular_recipes)} рецептов из Spoonacular")
        else:
            # Если уже достаточно из базовой базы и пользовательских, не используем Spoonacular
            logger.debug(f"✅ Достаточно рецептов из базовой базы и пользовательских, Spoonacular не используется")
    
        # Сортируем по релевантности: сначала базовая база (relevance_score), потом по usedIngredientCount
        all_recipes.sort(key=lambda x: (
            x.get("relevance_score", 0) if "base" in str(x.get("id", "")) else 0,
            x.get("usedIngredientCount", 0)
        ), reverse=True)
    
        # Ограничиваем результат до 8 рецептов
        all_recipes = all_recipes[:8]

        # Кэшируем итоговый список (с рецептами каналов/профилей и полями author), не только Spoonacular
        try:
            redis_client.setex(
                cache_key, CACHE_TTL, json.dumps(all_recipes, ensure_ascii=False)
            )
        except Exception as e:
            logger.warning("Redis cache save error (continuing without cache): %s", e)
    
        store_history_entry(ingredients, None, requested_mode)

        meta_out: Dict[str, Any] = {"mode": requested_mode, "language": lang}
        if can_localize:
            meta_out["recipe_translation_enabled"] = True
        elif any(card_needs_localization(c, lang) for c in all_recipes):
            meta_out["recipe_translation_requires_ai"] = True
        return {"recipes": all_recipes, "meta": meta_out}
    except Exception as e:
        logger.warning(f"Error searching recipes: {e}")
        # В случае ошибки все равно пытаемся вернуть рецепты из каналов и профилей
        try:
            channel_recipes = search_user_recipes(ingredients, db, limit=10)
            return {"recipes": channel_recipes, "meta": {"mode": requested_mode, "language": lang}}
        except Exception as e:
            logger.warning(f"⚠️ Error fetching user recipes: {e}")
            return {"recipes": [], "meta": {"mode": requested_mode, "language": lang}}


_SPOONACULAR_CARD_SIZE_RE = re.compile(
    r"-\d+x\d+(?=\.(jpg|jpeg|png|webp)$)", re.IGNORECASE
)


def _spoonacular_card_image_url(url: Optional[str]) -> Optional[str]:
    """Меньшее превью Spoonacular — 556x370 из РФ часто грузится десятки секунд."""
    if not url:
        return None
    u = url.strip()
    if not u:
        return None
    if "spoonacular.com" in u.lower():
        return _SPOONACULAR_CARD_SIZE_RE.sub("-312x231", u)
    return u


def _proxy_allowed_image_url(image_url: str) -> bool:
    """Разрешённые источники для прокси (CORS Web + стабильная загрузка аватаров на мобильных)."""
    u = (image_url or "").strip()
    if not u.startswith("https://"):
        return False
    prefixes = (
        "https://img.spoonacular.com",
        "https://spoonacular.com",
        "https://firebasestorage.googleapis.com",
        "https://lh3.googleusercontent.com",
        "https://lh4.googleusercontent.com",
        "https://lh5.googleusercontent.com",
        "https://lh6.googleusercontent.com",
        "https://pbs.twimg.com",
        "https://avatars.githubusercontent.com",
        "https://secure.gravatar.com",
        "https://www.gravatar.com",
        "https://cdn.discordapp.com",
        "https://storage.googleapis.com",
        "https://s3.twcstorage.ru",
    )
    low = u.lower()
    return any(low.startswith(p) for p in prefixes)


def _fetch_proxied_image(url: str) -> Response:
    """Прокси для изображений (CORS Web + внешние HTTPS на мобильных)."""
    import urllib.parse

    if url.startswith("http"):
        image_url = url
    else:
        image_url = urllib.parse.unquote(url)

    if not _proxy_allowed_image_url(image_url):
        raise HTTPException(status_code=400, detail="Invalid image URL")

    resp = requests.get(
        image_url,
        timeout=10,
        stream=True,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        },
    )
    if resp.status_code != 200:
        logger.warning(f"❌ Image proxy error: {resp.status_code} for {image_url[:80]}...")
        raise HTTPException(status_code=resp.status_code, detail="Failed to fetch image")

    content_type = resp.headers.get("Content-Type", "image/jpeg")

    return Response(
        content=resp.content,
        media_type=content_type,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Cache-Control": "public, max-age=86400",
        },
    )


@router.get("/recipe-image-proxy")
async def proxy_recipe_image_v2(
    url: str = Query(..., description="URL изображения для проксирования"),
):
    """
    Прокси изображений без префикса /recipes/{id} — иначе на части деплоев
    путь перехватывается GET /recipes/{recipe_id} (422 для recipe_id=image-proxy).
    """
    try:
        return _fetch_proxied_image(url)
    except HTTPException:
        raise
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching image: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


@router.get("/recipes/image-proxy")
async def proxy_recipe_image(url: str = Query(..., description="URL изображения для проксирования")):
    """Устаревший путь; оставлен для совместимости."""
    try:
        return _fetch_proxied_image(url)
    except HTTPException:
        raise
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching image: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


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
        from sqlalchemy import func

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
        meal_plan_count = _meal_plan_count_for_recipe_id(db, str(recipe_id))
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


def _food_scan_recipe_cards_from_search(
    dish_name: str,
    db: Session,
    *,
    lang: str = "ru",
) -> List[Dict[str, Any]]:
    """Похожие рецепты: база HAN Eat → каналы/профили → Spoonacular."""
    query = (dish_name or "").strip()
    if not query:
        return []

    cards: List[Dict[str, Any]] = []
    if lang == "ru":
        cards.extend(search_base_recipes(query, db, limit=4))
    if len(cards) < 8:
        cards.extend(search_user_recipes(query, db, limit=8 - len(cards)))

    if len(cards) >= 8 or not SPOONACULAR_API_KEY:
        return cards[:8]

    def _fetch(q: str) -> List[Dict[str, Any]]:
        try:
            resp = requests.get(
                "https://api.spoonacular.com/recipes/complexSearch",
                params={
                    "query": q,
                    "number": 8,
                    "addRecipeInformation": "true",
                    "apiKey": SPOONACULAR_API_KEY,
                },
                timeout=14,
            )
            if resp.status_code != 200:
                return []
            return resp.json().get("results") or []
        except Exception as exc:
            logger.debug("food scan complexSearch failed: %s", exc)
            return []

    rows = _fetch(query)
    if not rows:
        en_query = translate_query_to_english_for_spoonacular(query)
        if en_query:
            rows = _fetch(en_query)

    for rec in rows[: max(0, 8 - len(cards))]:
        image = rec.get("image")
        card_image = _spoonacular_card_image_url(image) if image else None
        orig_title = (rec.get("title") or "").strip()
        if not orig_title:
            continue
        cards.append(
            {
                "id": rec.get("id"),
                "title": orig_title,
                "translated_title": orig_title,
                "image": build_proxy(card_image) if card_image else None,
                "source_image": card_image or image,
                "source": "spoonacular",
                "ingredients": [],
                "steps": [],
                "usedIngredientCount": 0,
                "confidence": None,
            }
        )
    return cards


@router.post("/analyze")
async def analyze_photo(
    image_base64: Optional[str] = Body(None, description="Изображение в base64"),
    image_url: Optional[str] = Body(None, description="URL изображения"),
    mode: Optional[str] = Body(None, description="Режим анализа"),
    language: Optional[str] = Body(None, description="Язык"),
    ai_scan_ticket: Optional[str] = Body(None, description="JWT после POST /ai-scan/reserve"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user_required),
):
    """
    Анализ фото еды (Spoonacular). Требуется вход и билет после резерва кредита AI scan.
    """
    from app.core.entitlements import AI_SCAN_RESERVE_REQUIRED_CODE
    from app.core.security import verify_ai_scan_ticket
    from app.services.food_scan_gpt_service import analyze_food_photo_gpt
    from app.services.image_processing_service import optimize_scan_image_for_ai

    if not ai_scan_ticket or not verify_ai_scan_ticket(ai_scan_ticket, current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": AI_SCAN_RESERVE_REQUIRED_CODE,
                "message": "Сначала забронируйте AI scan в приложении",
            },
        )

    if not image_base64 and not image_url:
        raise HTTPException(status_code=400, detail="image_base64 or image_url required")

    use_spoonacular = bool(SPOONACULAR_API_KEY)
    use_gpt = bool((settings.OPENAI_API_KEY or "").strip())
    if not use_spoonacular and not use_gpt:
        raise HTTPException(
            status_code=502,
            detail="Сервис анализа не настроен (нужен Spoonacular или OpenAI)",
        )
    
    user_settings = get_user_settings()
    lang = (language or user_settings.get("language", DEFAULT_LANGUAGE)).lower()
    requested_mode = normalize_mode(mode or user_settings.get("analysis_mode", DEFAULT_MODE))
    
    raw = None
    gpt_result: Optional[Dict[str, Any]] = None
    url = "https://api.spoonacular.com/food/images/analyze"
    last_spoonacular_status: Optional[int] = None
    last_spoonacular_hint: str = ""

    def _spoonacular_analyze(img: bytes) -> requests.Response:
        return requests.post(
            url,
            params={"apiKey": SPOONACULAR_API_KEY},
            files={"file": ("capture.jpg", img, "image/jpeg")},
            timeout=40,
        )

    try:
        if image_base64:
            try:
                cleaned = image_base64.split(",")[-1]
                image_bytes = base64.b64decode(cleaned)
            except Exception as exc:
                raise HTTPException(status_code=400, detail=f"invalid base64 payload: {exc}")
            image_bytes = optimize_scan_image_for_ai(image_bytes)
        else:
            try:
                with requests.get(
                    image_url,
                    timeout=20,
                    stream=True,
                    headers={"User-Agent": "HANEat/1.0"},
                ) as ir:
                    ir.raise_for_status()
                    buf = bytearray()
                    for chunk in ir.iter_content(chunk_size=65536):
                        if not chunk:
                            continue
                        buf.extend(chunk)
                        if len(buf) > 12 * 1024 * 1024:
                            raise HTTPException(
                                status_code=400,
                                detail="image too large",
                            )
                image_bytes = optimize_scan_image_for_ai(bytes(buf))
            except HTTPException:
                raise
            except Exception as exc:
                raise HTTPException(
                    status_code=400,
                    detail=f"failed to fetch image_url: {exc}",
                )

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            spoon_future = (
                executor.submit(_spoonacular_analyze, image_bytes)
                if use_spoonacular
                else None
            )
            gpt_future = (
                executor.submit(analyze_food_photo_gpt, image_bytes, lang)
                if use_gpt
                else None
            )
            if spoon_future is not None:
                resp = spoon_future.result()
                last_spoonacular_status = resp.status_code
                if resp.status_code != 200:
                    last_spoonacular_hint = (resp.text or "")[:240]
                if resp.status_code == 200:
                    raw = resp.json()
            if gpt_future is not None:
                gpt_result = gpt_future.result()

        if not raw:
            gpt_usable = bool(
                gpt_result
                and (
                    (gpt_result.get("dish_name") or "").strip()
                    or gpt_result.get("nutrition")
                    or gpt_result.get("calories") is not None
                )
            )
            if gpt_usable:
                raw = {
                    "category": {
                        "name": (gpt_result.get("dish_name") or "").strip(),
                    },
                    "recipes": [],
                    "nutrition": {},
                    "confidence": gpt_result.get("confidence"),
                }
                logger.info(
                    "food scan: Spoonacular unavailable (%s), using GPT-only",
                    last_spoonacular_status,
                )
            else:
                detail = "analysis failed"
                if last_spoonacular_status:
                    detail = f"analysis failed (spoonacular HTTP {last_spoonacular_status})"
                    if last_spoonacular_hint:
                        detail = f"{detail}: {last_spoonacular_hint}"
                raise HTTPException(status_code=502, detail=detail)
        
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
        # Перевод категории в hot-path откладываем — клиент показывает label сразу.
        
        def _recipe_matches_dish(title: str, dish: str) -> bool:
            dish_n = (dish or "").strip().lower()
            title_n = (title or "").strip().lower()
            if not dish_n or not title_n:
                return False
            if dish_n in title_n or title_n in dish_n:
                return True
            dish_words = [w for w in dish_n.replace("-", " ").split() if len(w) >= 3]
            return any(w in title_n for w in dish_words)

        recipes_raw = (raw.get("recipes", []) or [])[:12]
        recipes = []
        for rec in recipes_raw:
            image = rec.get("image")
            card_image = _spoonacular_card_image_url(image) if image else None
            orig_title = (rec.get("title") or "").strip()
            # Перевод каждого рецепта в hot-path сильно замедляет ответ; заголовок — как в Spoonacular.
            translated_title_val = orig_title
            recipes.append({
                "id": rec.get("id"),
                "title": orig_title,
                "translated_title": translated_title_val,
                "image": build_proxy(card_image) if card_image else None,
                "source_image": card_image or image,
                "source": "spoonacular",
                "ingredients": [],
                "steps": [],
                "usedIngredientCount": 0,
                "confidence": rec.get("confidence"),
            })

        def _has_macro_nutrition(nut: dict) -> bool:
            for key in ("protein", "fat", "carbohydrates", "carbs"):
                val = nut.get(key)
                if isinstance(val, (int, float)) and val > 0:
                    return True
            return False

        portion_grams = None
        nutrition_source = "spoonacular"
        dish_for_match = category_name or category.get("name") or ""
        if gpt_result:
            gpt_nutrition = gpt_result.get("nutrition") or {}
            gpt_name = (gpt_result.get("dish_name") or "").strip()
            if gpt_name:
                dish_for_match = gpt_name
            if gpt_nutrition:
                if not simplified_nutrition or not _has_macro_nutrition(simplified_nutrition):
                    simplified_nutrition = {
                        k: v
                        for k, v in gpt_nutrition.items()
                        if isinstance(v, (int, float))
                    }
                    nutrition_source = "gpt"
                elif _has_macro_nutrition(gpt_nutrition):
                    for k, v in gpt_nutrition.items():
                        if isinstance(v, (int, float)) and (
                            k not in simplified_nutrition
                            or not simplified_nutrition.get(k)
                        ):
                            simplified_nutrition[k] = v
                    nutrition_source = "gpt+spoonacular"
            if gpt_result.get("calories") is not None:
                calories = gpt_result["calories"]
                if nutrition_source == "spoonacular":
                    nutrition_source = "gpt"
            if gpt_result.get("portion_grams") is not None:
                portion_grams = gpt_result["portion_grams"]
            gpt_conf = gpt_result.get("confidence")
            if gpt_conf is not None and confidence is None:
                confidence = gpt_conf

        if dish_for_match and recipes:
            matched = [
                r
                for r in recipes
                if _recipe_matches_dish(r.get("title") or "", dish_for_match)
            ]
            if matched:
                recipes = matched[:8]

        if not recipes and dish_for_match:
            recipes = _food_scan_recipe_cards_from_search(
                dish_for_match, db, lang=lang
            )

        display_label = dish_for_match or category_name or category.get("name")
        analysis = {
            "label": display_label,
            "translated_label": display_label,
            "confidence": confidence,
            "nutrition": simplified_nutrition,
            "calories": calories,
            "recipes": recipes,
            "portion_grams": portion_grams,
        }

        AnalyticsService(db).log_event(
            event_type="ai_scan_analyze",
            entity_type="user",
            entity_id=current_user.id,
            user_id=current_user.id,
            metadata={
                "mode": requested_mode,
                "language": lang,
                "nutrition_source": nutrition_source,
            },
        )
        db.commit()

        return {"analysis": analysis, "mode": requested_mode, "language": lang}
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Error analyzing photo: {e}")
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


def _favorites_redis_key(user_id: int) -> str:
    return f"favorites:{user_id}"


@router.get("/favorites")
async def get_favorites(
    current_user: User = Depends(get_current_user_required),
):
    """Получить избранные рецепты текущего пользователя."""
    try:
        favorites_json = redis_client.get(_favorites_redis_key(current_user.id)) or "{}"
        favorites = json.loads(favorites_json)
        favs = list(favorites.values())
        favs.sort(key=lambda x: x.get("ts", 0), reverse=True)
        return {"favorites": favs}
    except Exception as e:
        logger.warning(f"Error getting favorites: {e}")
        return {"favorites": []}


@router.post("/favorites")
async def add_favorite(
    body: Dict[str, Any] = Body(..., description="Тело запроса"),
    current_user: User = Depends(get_current_user_required),
):
    """Добавить рецепт в избранное"""
    # Поддерживаем два формата: прямой рецепт или {"recipe": {...}}
    recipe = body.get("recipe") if "recipe" in body else body
    
    if not isinstance(recipe, dict):
        logger.warning(f"⚠️ Recipe is not a dict: {type(recipe)}")
        raise HTTPException(status_code=400, detail="recipe must be a dictionary")
    
    rid = recipe.get("id")
    if rid is None:
        logger.warning(f"⚠️ Recipe has no id. Keys: {list(recipe.keys())}")
        raise HTTPException(status_code=400, detail="recipe has no id")
    
    # Убеждаемся, что ID - это число
    if not isinstance(rid, (int, float)):
        try:
            rid = int(rid)
            recipe["id"] = rid  # Обновляем ID в рецепте
        except (ValueError, TypeError):
            logger.warning(f"⚠️ Recipe id is not a number: {rid} (type: {type(rid)})")
            raise HTTPException(status_code=400, detail=f"recipe id must be a number, got: {type(rid).__name__}")
    
    try:
        key = _favorites_redis_key(current_user.id)
        favorites_json = redis_client.get(key) or "{}"
        favorites = json.loads(favorites_json)
        recipe["ts"] = int(time.time())
        favorites[str(rid)] = recipe
        redis_client.set(key, json.dumps(favorites, ensure_ascii=False))
        return {"ok": True}
    except Exception as e:
        logger.warning(f"Error adding favorite: {e}")
        raise HTTPException(status_code=500, detail="failed to add favorite")


@router.delete("/favorites/{rid}")
async def remove_favorite(
    rid: int,
    current_user: User = Depends(get_current_user_required),
):
    """Удалить рецепт из избранного"""
    try:
        key = _favorites_redis_key(current_user.id)
        favorites_json = redis_client.get(key) or "{}"
        favorites = json.loads(favorites_json)
        if str(rid) in favorites:
            del favorites[str(rid)]
            redis_client.set(key, json.dumps(favorites, ensure_ascii=False))
        return {"ok": True}
    except Exception as e:
        logger.warning(f"Error removing favorite: {e}")
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
        logger.warning(f"Error getting history: {e}")
        return {"history": []}


@router.delete("/history")
async def clear_history():
    """Очистить историю поиска"""
    try:
        redis_client.delete("search_history")
        return {"ok": True}
    except Exception as e:
        logger.warning(f"Error clearing history: {e}")
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
        logger.warning(f"Error getting recipe comments: {e}")
        return {"comments": []}


@router.post("/recipes/{recipe_id}/comments")
async def add_recipe_comment(
    recipe_id: int,
    author: Optional[str] = Body(None, description="Автор комментария"),
    text: str = Body(..., description="Текст комментария"),
    author_avatar: Optional[str] = Body(None, description="Аватар автора"),
    author_id: Optional[str] = Body(None, description="ID автора для проверки прав"),
    parent_id: Optional[int] = Body(None, description="ID родительского комментария"),
    rating: Optional[int] = Body(None, ge=1, le=5, description="Рейтинг от 1 до 5"),
):
    """Добавить комментарий к рецепту"""
    if (text is None or not text.strip()) and rating is None:
        raise HTTPException(status_code=400, detail="Text or rating is required")
    
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
        
        now_ts = int(time.time())
        rating_updated = False

        # Если передан рейтинг и известен author_id:
        # один пользователь может иметь только одну оценку на рецепт.
        # При повторной оценке обновляем существующую запись вместо создания новой.
        # ВАЖНО: ответы (parent_id != None) всегда создаются как отдельные комментарии.
        existing_rated_index = None
        if rating is not None and author_id and parent_id is None:
            for i, c in enumerate(comments):
                if c.get("author_id") == author_id and c.get("rating") is not None:
                    existing_rated_index = i
                    break

        if existing_rated_index is not None:
            existing = comments[existing_rated_index]
            existing["rating"] = rating
            if text is not None and text.strip():
                existing["text"] = text.strip()
            if author:
                existing["author"] = author
            if author_avatar:
                existing["author_avatar"] = author_avatar
            # Всплытие наверх как "новая" активность после изменения оценки
            existing["created_at"] = now_ts
            new_comment = existing
            rating_updated = True
        else:
            # Создаем новый комментарий
            # ID должен быть int, но используем timestamp для уникальности
            comment_id = int(time.time() * 1000)
            new_comment = {
                "id": comment_id,
                "recipe_id": str(recipe_id),  # Фронтенд ожидает String
                "author": author or "Anonymous",
                "author_id": author_id,  # ID автора для проверки прав удаления
                "author_avatar": author_avatar,
                "text": (text or "").strip(),
                "parent_id": parent_id,
                "rating": rating,  # Рейтинг от 1 до 5
                "created_at": now_ts,
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
        
        return {"ok": True, "comment": new_comment, "rating_updated": rating_updated}
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
        
        # Вычисляем средний рейтинг.
        # Для авторизованных пользователей учитываем только последнюю оценку
        # (по факту у них и так 1 запись, но это защищает от старых дублей).
        user_ratings: Dict[str, int] = {}
        anon_ratings: List[int] = []
        for c in comments:
            r = c.get("rating")
            if r is None:
                continue
            try:
                r_int = int(r)
            except (TypeError, ValueError):
                continue
            if r_int < 1 or r_int > 5:
                continue
            aid = c.get("author_id")
            if aid:
                user_ratings[str(aid)] = r_int
            else:
                anon_ratings.append(r_int)

        ratings = list(user_ratings.values()) + anon_ratings
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
        logger.warning(f"Error updating recipe rating: {e}")


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
        logger.warning(f"Error deleting recipe comment: {e}")
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
        logger.warning(f"Error getting recipe rating: {e}")
        return {"rating": 0.0, "count": 0}
