# app.py
import base64
import json
import os
import re
import sqlite3
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote, urlparse

import requests
from dotenv import load_dotenv
from flask import (
    Flask,
    Response,
    abort,
    g,
    jsonify,
    request,
    send_from_directory,
    has_request_context,
)
from flask_cors import CORS

# Попробуем импортировать переводчик
try:
    from googletrans import Translator
    TRANSLATOR_AVAILABLE = True
except (ImportError, AttributeError) as e:
    print(f"⚠️ Googletrans не установлен или несовместим, переводы отключены: {e}")
    TRANSLATOR_AVAILABLE = False
    Translator = None

try:
    from langdetect import DetectorFactory, LangDetectException, detect
    LANGDETECT_AVAILABLE = True
except ImportError:
    print("⚠️ Langdetect не установлен")
    LANGDETECT_AVAILABLE = False
    DetectorFactory = None
    LangDetectException = Exception
    detect = None

# ---------------- config ----------------
# load .env from the same folder as this file
dotenv_path = Path(__file__).resolve().parent / ".env"
load_dotenv(dotenv_path=dotenv_path)

SPOONACULAR_API_KEY = os.getenv("SPOONACULAR_API_KEY")
if not SPOONACULAR_API_KEY:
    print("❌ SPOONACULAR_API_KEY не найден в .env файле")
    print("Создайте .env файл со строкой:")
    print("SPOONACULAR_API_KEY=ваш_api_ключ")
    exit(1)

print(f"✅ SPOONACULAR_API_KEY найден: {SPOONACULAR_API_KEY[:10]}...")

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = os.path.join(BASE_DIR, "recipeapp.db")
CACHE_TTL = 12 * 3600  # 12 hours cache
RECOMMENDATIONS_CACHE_TTL = 3 * 60  # 3 minutes cache for recommendations (для разнообразия рецептов)
MAX_HISTORY_ENTRIES = 50
DEFAULT_LANGUAGE = os.getenv("HAN_DEFAULT_LANGUAGE", "ru")
DEFAULT_MODE = os.getenv("HAN_DEFAULT_MODE", "all")
ALLOWED_MODES = {"recipe", "calories", "all"}
UPLOAD_DIR = BASE_DIR / "uploads"
VIDEOS_DIR = UPLOAD_DIR / "videos"
THUMBS_DIR = UPLOAD_DIR / "thumbnails"
for path in (UPLOAD_DIR, VIDEOS_DIR, THUMBS_DIR):
    path.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# Инициализация переводчика если доступен
translator = None
if TRANSLATOR_AVAILABLE and Translator is not None:
    try:
        translator = Translator(service_urls=["translate.googleapis.com"])
    except Exception as e:
        print(f"⚠️ Не удалось инициализировать переводчик: {e}")
        translator = None
        TRANSLATOR_AVAILABLE = False
if LANGDETECT_AVAILABLE and DetectorFactory:
    DetectorFactory.seed = 0


# ---------------- DB helpers ----------------
def get_db():
    db = getattr(g, "_database", None)
    if db is None:
        db = g._database = sqlite3.connect(DB_PATH, check_same_thread=False)
        db.row_factory = sqlite3.Row
    return db


def init_db():
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS cached_recipes (
        key TEXT PRIMARY KEY,
        json TEXT,
        ts INTEGER
    )"""
    )
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS favorites (
        recipe_id INTEGER PRIMARY KEY,
        json TEXT,
        ts INTEGER
    )"""
    )
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        filters TEXT,
        mode TEXT NOT NULL,
        ts INTEGER NOT NULL
    )"""
    )
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS user_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        analysis_mode TEXT NOT NULL,
        language TEXT NOT NULL
    )"""
    )
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS community_posts (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        avatar TEXT,
        description TEXT,
        video_url TEXT,
        thumbnail TEXT,
        video_local_path TEXT,
        thumbnail_local_path TEXT,
        likes INTEGER DEFAULT 0,
        tags TEXT,
        created_at INTEGER NOT NULL,
        status TEXT DEFAULT 'published'
    )"""
    )
    # Таблица для комментариев к рецептам
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS recipe_comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id TEXT NOT NULL,
        author TEXT NOT NULL,
        author_avatar TEXT,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT DEFAULT 'published'
    )"""
    )
    # Таблица для подписок на авторов
    cur.execute(
        """
    CREATE TABLE IF NOT EXISTS author_subscriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscriber TEXT NOT NULL,
        author TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(subscriber, author)
    )"""
    )
    db.commit()
    cur.execute(
        """
    INSERT OR IGNORE INTO user_settings (id, analysis_mode, language)
    VALUES (1, ?, ?)
    """,
        (DEFAULT_MODE, DEFAULT_LANGUAGE),
    )
    db.commit()
    ensure_community_columns()
    seed_community_posts()


@app.teardown_appcontext
def close_connection(exc):
    db = getattr(g, "_database", None)
    if db is not None:
        db.close()


# ---------------- util helpers ----------------
TRANSLATION_CACHE: Dict[str, str] = {}


def normalize_mode(raw: Optional[str]) -> str:
    if not raw:
        return DEFAULT_MODE
    value = raw.strip().lower()
    if value not in ALLOWED_MODES:
        return DEFAULT_MODE
    return value


def detect_language_safe(text: str) -> Optional[str]:
    if not text or len(text.strip()) < 3 or not LANGDETECT_AVAILABLE or not detect:
        return None
    try:
        return detect(text)
    except Exception:
        return None


def translate_text(text: str, target_language: str) -> str:
    if not text or not TRANSLATOR_AVAILABLE or not translator:
        return text
    cache_key = f"{target_language}:{text}"
    if cache_key in TRANSLATION_CACHE:
        return TRANSLATION_CACHE[cache_key]
    try:
        result = translator.translate(text, dest=target_language)
        TRANSLATION_CACHE[cache_key] = result.text
        return result.text
    except Exception as e:
        print(f"Translation error: {e}")
        return text


def translate_list(items: List[str], target_language: str) -> List[str]:
    translated = []
    for item in items:
        translated.append(translate_text(item, target_language))
    return translated


def translate_steps(steps: List[Dict[str, Any]], target_language: str) -> List[Dict[str, Any]]:
    translated = []
    for step in steps:
        translated.append(
            {
                "number": step.get("number"),
                "step": translate_text(step.get("step", ""), target_language),
                "image": step.get("image"),
            }
        )
    return translated


def ensure_community_columns():
    db = get_db()
    cur = db.cursor()
    cur.execute("PRAGMA table_info(community_posts)")
    existing = {row["name"] for row in cur.fetchall()}
    alter_statements = []
    if "video_local_path" not in existing:
        alter_statements.append(
            "ALTER TABLE community_posts ADD COLUMN video_local_path TEXT"
        )
    if "thumbnail_local_path" not in existing:
        alter_statements.append(
            "ALTER TABLE community_posts ADD COLUMN thumbnail_local_path TEXT"
        )
    if "status" not in existing:
        alter_statements.append(
            "ALTER TABLE community_posts ADD COLUMN status TEXT DEFAULT 'published'"
        )
    for stmt in alter_statements:
        cur.execute(stmt)
    db.commit()


def seed_community_posts():
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT COUNT(*) as cnt FROM community_posts")
    if cur.fetchone()["cnt"] > 0:
        return
    now = int(time.time())
    sample_posts = [
        {
            "id": 1,
            "title": "Боулы для энергии",
            "author": "Аня Wellness",
            "avatar": "https://i.pravatar.cc/150?img=47",
            "description": "Собрала теплый боул с киноа, шпинатом и нутом. Соус на тахини без сахара.",
            "video_url": "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
            "thumbnail": "https://images.unsplash.com/photo-1504674900247-0877df9cc836",
            "likes": 482,
            "tags": ["боул", "здоровье", "vegan"],
            "created_at": now - 3600,
            "status": "published",
        },
        {
            "id": 2,
            "title": "Фитнес-роллы с лососем",
            "author": "Chef Nikita",
            "avatar": "https://i.pravatar.cc/150?img=12",
            "description": "Роллы без риса: огурец, лосось, соус юдзу + лайфхаки по нарезке.",
            "video_url": "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4",
            "thumbnail": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?ixid=Mnwx",
            "likes": 311,
            "tags": ["рыба", "кето"],
            "created_at": now - 7200,
            "status": "published",
        },
        {
            "id": 3,
            "title": "Рамен 15 минут",
            "author": "Tokio Home",
            "avatar": "https://i.pravatar.cc/150?img=33",
            "description": "Быстрый мисо-рамен с грибами шиитаке и яйцом софт.",
            "video_url": "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
            "thumbnail": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c",
            "likes": 905,
            "tags": ["рамен", "comfort"],
            "created_at": now - 18000,
            "status": "published",
        },
    ]
    for post in sample_posts:
        cur.execute(
            """
        INSERT OR REPLACE INTO community_posts
        (id, title, author, avatar, description, video_url, thumbnail, likes, tags, created_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                post["id"],
                post["title"],
                post["author"],
                post["avatar"],
                post["description"],
                post["video_url"],
                post["thumbnail"],
                post["likes"],
                json.dumps(post["tags"], ensure_ascii=False),
                post["created_at"],
                post["status"],
            ),
        )
    db.commit()


def fetch_nutrition(recipe_id: int) -> Optional[Dict[str, Any]]:
    url = f"https://api.spoonacular.com/recipes/{recipe_id}/nutritionWidget.json"
    resp = requests.get(url, params={"apiKey": SPOONACULAR_API_KEY}, timeout=20)
    if resp.status_code == 200:
        return resp.json()
    return None


def extract_calories(nutrition: Optional[Dict[str, Any]]) -> Optional[int]:
    if not nutrition:
        return None
    calories = nutrition.get("calories")
    if isinstance(calories, (int, float)):
        return int(calories)
    if isinstance(calories, str):
        digits = re.findall(r"\d+", calories)
        if digits:
            return int(digits[0])
    # Пробуем извлечь калории из массива nutrients
    if isinstance(nutrition.get("nutrients"), list):
        for n in nutrition["nutrients"]:
            name = str(n.get("name", "")).lower()
            if "calorie" in name or "energy" in name:
                amount = n.get("amount")
                if amount is not None:
                    return int(amount) if isinstance(amount, (int, float)) else None
    return None


def extract_nutrient_value(nutrition: Optional[Dict[str, Any]], nutrient_key: str) -> Optional[float]:
    """Извлекает значение питательного вещества из nutrition объекта (белки, жиры, углеводы)"""
    if not nutrition:
        return None
    value = nutrition.get(nutrient_key)
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Извлекаем число из строки типа "20g" или "20 g"
        digits = re.findall(r"(\d+\.?\d*)", value)
        if digits:
            try:
                return float(digits[0])
            except ValueError:
                return None
    return None


def extract_macros_from_nutrition(nutrition: Optional[Dict[str, Any]]) -> Dict[str, Optional[float]]:
    """Извлекает белки, жиры и углеводы из nutrition объекта Spoonacular"""
    if not nutrition:
        print("⚠️ extract_macros_from_nutrition: nutrition is None")
        return {"protein": None, "fat": None, "carbs": None}
    
    print(f"🔍 extract_macros_from_nutrition: nutrition keys={list(nutrition.keys())}")
    
    # Пробуем разные варианты ключей
    protein = None
    fat = None
    carbs = None
    
    # Вариант 1: прямые ключи
    if "protein" in nutrition:
        protein = extract_nutrient_value(nutrition, "protein")
    if "fat" in nutrition:
        fat = extract_nutrient_value(nutrition, "fat")
    if "carbs" in nutrition or "carbohydrates" in nutrition:
        carbs = extract_nutrient_value(nutrition, "carbs") or extract_nutrient_value(nutrition, "carbohydrates")
    
    # Вариант 2: массив nutrients (основной способ для Spoonacular)
    if protein is None or fat is None or carbs is None:
        nutrients = nutrition.get("nutrients") or nutrition.get("nutrition", {}).get("nutrients", [])
        if isinstance(nutrients, list):
            print(f"🔍 Found {len(nutrients)} nutrients in array")
            for n in nutrients:
                name = str(n.get("name", "")).lower()
                amount = n.get("amount")
                unit = n.get("unit", "").lower()
                title = str(n.get("title", "")).lower()  # Иногда используется title вместо name
                
                # Используем title если name пустой
                search_name = title if not name and title else name
                
                if amount is not None:
                    # Ищем белки (пробуем разные варианты названий)
                    if protein is None and ("protein" in search_name or search_name == "proteins"):
                        protein = float(amount) if isinstance(amount, (int, float)) else None
                        print(f"✅ Found protein: {protein} from '{search_name}' (name: {name}, title: {title})")
                    # Ищем жиры (исключаем saturated, trans, но берем total fat)
                    elif fat is None and ("fat" in search_name):
                        if "saturated" not in search_name and "trans" not in search_name and "polyunsaturated" not in search_name and "monounsaturated" not in search_name:
                            fat = float(amount) if isinstance(amount, (int, float)) else None
                            print(f"✅ Found fat: {fat} from '{search_name}' (name: {name}, title: {title})")
                        elif "total" in search_name or search_name == "fat":
                            fat = float(amount) if isinstance(amount, (int, float)) else None
                            print(f"✅ Found fat (total): {fat} from '{search_name}' (name: {name}, title: {title})")
                    # Ищем углеводы
                    elif carbs is None and ("carb" in search_name or "carbohydrate" in search_name):
                        if "net" not in search_name or search_name == "net carbohydrates":
                            carbs = float(amount) if isinstance(amount, (int, float)) else None
                            print(f"✅ Found carbs: {carbs} from '{search_name}' (name: {name}, title: {title})")
            
            # Если не нашли, выводим все доступные названия для отладки
            if protein is None or fat is None or carbs is None:
                print(f"⚠️ Not all macros found. Available nutrients: {[n.get('name', n.get('title', 'unknown')) for n in nutrients[:10]]}")
    
    # Вариант 3: caloricBreakdown (если есть) - используем как fallback
    if (protein is None or fat is None or carbs is None) and "caloricBreakdown" in nutrition:
        caloric = nutrition["caloricBreakdown"]
        print(f"🔍 Found caloricBreakdown: {caloric}")
        calories_val = nutrition.get("calories")
        print(f"🔍 caloricBreakdown: calories_val from nutrition.get('calories')={calories_val}")
        if not calories_val:
            # Пробуем извлечь калории из массива nutrients
            if isinstance(nutrition.get("nutrients"), list):
                print(f"🔍 Searching for calories in {len(nutrition['nutrients'])} nutrients")
                for n in nutrition["nutrients"]:
                    name = str(n.get("name", "")).lower()
                    title = str(n.get("title", "")).lower()
                    search_name = title if not name and title else name
                    if "calorie" in search_name or "energy" in search_name:
                        calories_val = n.get("amount")
                        print(f"🔍 Found calories in nutrients: {calories_val} from '{search_name}' (name: {name}, title: {title})")
                        break
            # Если не нашли, пробуем из recipe
            if not calories_val:
                # Пробуем получить калории из рецепта (если он передан)
                # Но здесь у нас нет доступа к recipe, поэтому используем estimate
                print(f"⚠️ No calories found in nutrition, will use estimated calories")
        
        if calories_val:
            print(f"🔍 Using caloricBreakdown with calories={calories_val}, breakdown={caloric}")
            if protein is None and "protein" in caloric:
                # Вычисляем белки из процента калорий
                protein_pct = caloric.get("protein", 0)
                print(f"🔍 Protein percentage: {protein_pct}")
                if isinstance(protein_pct, (int, float)) and protein_pct > 0:
                    protein = (calories_val * protein_pct / 100) / 4.0  # 4 ккал на грамм белка
                    print(f"✅ Calculated protein from caloricBreakdown: {protein} ({protein_pct}% of {calories_val} cal)")
            if fat is None and "fat" in caloric:
                # Вычисляем жиры из процента калорий
                fat_pct = caloric.get("fat", 0)
                print(f"🔍 Fat percentage: {fat_pct}")
                if isinstance(fat_pct, (int, float)) and fat_pct > 0:
                    fat = (calories_val * fat_pct / 100) / 9.0  # 9 ккал на грамм жира
                    print(f"✅ Calculated fat from caloricBreakdown: {fat} ({fat_pct}% of {calories_val} cal)")
            if carbs is None and "carbs" in caloric:
                # Вычисляем углеводы из процента калорий
                carbs_pct = caloric.get("carbs", 0)
                print(f"🔍 Carbs percentage: {carbs_pct}")
                if isinstance(carbs_pct, (int, float)) and carbs_pct > 0:
                    carbs = (calories_val * carbs_pct / 100) / 4.0  # 4 ккал на грамм углеводов
                    print(f"✅ Calculated carbs from caloricBreakdown: {carbs} ({carbs_pct}% of {calories_val} cal)")
        else:
            print(f"⚠️ caloricBreakdown found but no calories value available")
    
    return {"protein": protein, "fat": fat, "carbs": carbs}


def estimate_calories_from_ingredients(ingredients: List[str]) -> Optional[int]:
    """Оценивает калории на основе ингредиентов (для пользовательских рецептов)"""
    if not ingredients:
        # Если ингредиентов нет, возвращаем базовое значение
        return 300  # Среднее значение для рецепта
    
    # Средние калории на ингредиент (примерно 50-80 ккал на ингредиент)
    # Это упрощенная оценка, можно улучшить используя базу данных продуктов
    calories_per_ingredient = 65  # среднее значение
    
    # Учитываем количество ингредиентов
    num_ingredients = len(ingredients)
    
    # Базовая оценка
    estimated_calories = calories_per_ingredient * num_ingredients
    
    # Минимальные и максимальные значения для реалистичности
    min_calories = 100
    max_calories = 1500
    
    estimated_calories = max(min_calories, min(estimated_calories, max_calories))
    
    return int(estimated_calories)


def estimate_macros_from_ingredients(ingredients: List[str], calories: Optional[int] = None) -> Dict[str, float]:
    """Оценивает БЖУ на основе ингредиентов (для пользовательских рецептов)
    Всегда возвращает значения (не None)"""
    # Если калории не переданы, вычисляем их
    if calories is None:
        calories = estimate_calories_from_ingredients(ingredients)
    
    # Если есть калории, вычисляем БЖУ на их основе
    if calories and calories > 0:
        # Средние калории: белки 4 ккал/г, жиры 9 ккал/г, углеводы 4 ккал/г
        # Пропорции: 20% белки, 30% жиры, 50% углеводы (типичное соотношение)
        estimated_protein = (calories * 0.20) / 4.0
        estimated_fat = (calories * 0.30) / 9.0
        estimated_carbs = (calories * 0.50) / 4.0
    else:
        # Средние значения БЖУ на 100г для разных категорий ингредиентов
        # Это упрощенная оценка, можно улучшить используя базу данных продуктов
        protein_per_ingredient = 5.0  # грамм белка на ингредиент
        fat_per_ingredient = 3.0      # грамм жира на ингредиент
        carbs_per_ingredient = 8.0    # грамм углеводов на ингредиент
        
        # Учитываем количество ингредиентов (минимум 1 для избежания нулевых значений)
        num_ingredients = max(1, len(ingredients))
        
        # Базовые оценки
        estimated_protein = protein_per_ingredient * num_ingredients
        estimated_fat = fat_per_ingredient * num_ingredients
        estimated_carbs = carbs_per_ingredient * num_ingredients
    
    # Убеждаемся, что значения не нулевые (минимум 1.0)
    estimated_protein = max(1.0, estimated_protein)
    estimated_fat = max(1.0, estimated_fat)
    estimated_carbs = max(1.0, estimated_carbs)
    
    return {
        "protein": round(estimated_protein, 1),
        "fat": round(estimated_fat, 1),
        "carbs": round(estimated_carbs, 1)
    }


def ensure_nutrition_data(recipe: Dict[str, Any], nutrition: Optional[Dict[str, Any]] = None) -> Tuple[Dict[str, Any], Optional[int]]:
    """Обеспечивает наличие данных о питании в рецепте, вычисляя их если нужно
    Возвращает (nutrition, calories)"""
    if nutrition is None:
        nutrition = recipe.get("nutrition")
    
    # Получаем текущие калории из рецепта или nutrition
    calories = recipe.get("calories")
    if calories is None and nutrition:
        calories = extract_calories(nutrition)
    
    # Получаем ингредиенты
    ingredients = recipe.get("ingredients", [])
    if not ingredients:
        # Если ингредиентов нет, используем пустой список (будет базовое значение)
        ingredients = []
    
    # Если калории отсутствуют, вычисляем их на основе ингредиентов
    if calories is None:
        calories = estimate_calories_from_ingredients(ingredients)
        # Обновляем калории в рецепте
        recipe["calories"] = calories
    
    # Извлекаем БЖУ из nutrition если есть
    recipe_id = recipe.get('id', 'unknown')
    print(f"🔍 ensure_nutrition_data для рецепта {recipe_id}: nutrition keys={list(nutrition.keys()) if nutrition else 'None'}")
    if nutrition:
        print(f"🔍 ensure_nutrition_data для рецепта {recipe_id}: nutrition['calories']={nutrition.get('calories')}")
        print(f"🔍 ensure_nutrition_data для рецепта {recipe_id}: nutrition['caloricBreakdown']={nutrition.get('caloricBreakdown')}")
    macros = extract_macros_from_nutrition(nutrition)
    
    print(f"🔍 Extracted macros from nutrition: protein={macros['protein']}, fat={macros['fat']}, carbs={macros['carbs']}")
    
    # Всегда вычисляем БЖУ на основе ингредиентов (даже если есть частичные данные)
    estimated = estimate_macros_from_ingredients(ingredients, calories)
    
    print(f"🔍 Estimated macros from ingredients: protein={estimated['protein']}, fat={estimated['fat']}, carbs={estimated['carbs']}")
    
    # Используем реальные значения если есть, иначе используем вычисленные (estimated всегда возвращает значения)
    final_protein = macros["protein"] if macros["protein"] is not None else estimated["protein"]
    final_fat = macros["fat"] if macros["fat"] is not None else estimated["fat"]
    final_carbs = macros["carbs"] if macros["carbs"] is not None else estimated["carbs"]
    
    print(f"🔍 Final macros: protein={final_protein}, fat={final_fat}, carbs={final_carbs}")
    
    # Обновляем nutrition объект (всегда создаем новый, чтобы гарантировать наличие данных)
    if nutrition is None:
        nutrition = {}
    
    # Добавляем калории в nutrition
    if calories is not None:
        nutrition["calories"] = calories
    
    # Добавляем БЖУ в nutrition (всегда, значения гарантированно не None)
    nutrition["protein"] = final_protein
    nutrition["proteins"] = final_protein  # Дублируем для совместимости
    nutrition["fat"] = final_fat
    nutrition["fats"] = final_fat  # Дублируем для совместимости
    nutrition["carbs"] = final_carbs
    nutrition["carbohydrates"] = final_carbs  # Дублируем для совместимости
    nutrition["carb"] = final_carbs  # Дублируем для совместимости
    
    # Отладочный вывод
    print(f"📊 Nutrition для рецепта {recipe.get('id', 'unknown')}: protein={final_protein}, fat={final_fat}, carbs={final_carbs}, calories={calories}")
    print(f"📊 Nutrition object keys: {list(nutrition.keys())}")
    print(f"📊 Nutrition object (protein/fat/carbs): protein={nutrition.get('protein')}, fat={nutrition.get('fat')}, carbs={nutrition.get('carbs')}")
    
    return nutrition, calories


def ensure_history_limit(db):
    cur = db.cursor()
    cur.execute("SELECT COUNT(*) as cnt FROM search_history")
    count = cur.fetchone()["cnt"]
    if count > MAX_HISTORY_ENTRIES:
        to_delete = count - MAX_HISTORY_ENTRIES
        cur.execute(
            """
        DELETE FROM search_history
        WHERE id IN (
            SELECT id FROM search_history
            ORDER BY ts ASC
            LIMIT ?
        )
        """,
            (to_delete,),
        )
        db.commit()


def store_history_entry(query: str, filters: Optional[Dict[str, Any]], mode: str):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    INSERT INTO search_history (query, filters, mode, ts)
    VALUES (?, ?, ?, ?)
    """,
        (query, json.dumps(filters or {}, ensure_ascii=False), mode, int(time.time())),
    )
    db.commit()
    ensure_history_limit(db)


def get_history(limit: int = 25) -> List[Dict[str, Any]]:
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    SELECT query, filters, mode, ts
    FROM search_history
    ORDER BY ts DESC
    LIMIT ?
    """,
        (limit,),
    )
    rows = cur.fetchall()
    history = []
    for row in rows:
        history.append(
            {
                "query": row["query"],
                "filters": json.loads(row["filters"] or "{}"),
                "mode": row["mode"],
                "ts": row["ts"],
            }
        )
    return history


def get_user_settings() -> Dict[str, Any]:
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT analysis_mode, language FROM user_settings WHERE id = 1")
    row = cur.fetchone()
    if not row:
        return {"analysis_mode": DEFAULT_MODE, "language": DEFAULT_LANGUAGE}
    mode = normalize_mode(row["analysis_mode"])
    language = (row["language"] or DEFAULT_LANGUAGE).lower()
    return {"analysis_mode": mode, "language": language}


def update_user_settings(mode: Optional[str], language: Optional[str]) -> Dict[str, Any]:
    current = get_user_settings()
    new_mode = normalize_mode(mode or current["analysis_mode"])
    new_language = (language or current["language"] or DEFAULT_LANGUAGE).lower()
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    UPDATE user_settings
    SET analysis_mode = ?, language = ?
    WHERE id = 1
    """,
        (new_mode, new_language),
    )
    db.commit()
    return {"analysis_mode": new_mode, "language": new_language}


def attach_recipe_metadata(
    recipe: Dict[str, Any], info: Dict[str, Any], language: str, mode: str
) -> Dict[str, Any]:
    ingredients_list = recipe.get("ingredients", [])
    steps = recipe.get("steps", [])
    summary_source = recipe.get("summary") or info.get("summary") or ""

    detected_language = detect_language_safe(recipe.get("title", "")) or language
    needs_translation = language and detected_language != language

    translated_title = recipe.get("title")
    translated_ingredients = ingredients_list
    translated_steps = steps

    if needs_translation:
        translated_title = translate_text(recipe.get("title", ""), language)
        translated_ingredients = translate_list(ingredients_list, language)
        translated_steps = translate_steps(steps, language)

    nutrition = None
    calories = None
    if mode in {"calories", "all"}:
        nutrition = fetch_nutrition(recipe.get("id"))
        calories = extract_calories(nutrition)
    
    # Создаем объект рецепта для ensure_nutrition_data
    recipe_data = {
        **recipe,
        "ingredients": ingredients_list,
        "calories": calories,
    }
    
    # Обеспечиваем наличие калорий и БЖУ в nutrition (всегда, не только для режима calories/all)
    nutrition, final_calories = ensure_nutrition_data(recipe_data, nutrition)

    return {
        **recipe,
        "ingredients": ingredients_list,
        "steps": steps,
        "translated_title": translated_title,
        "translated_ingredients": translated_ingredients,
        "translated_steps": translated_steps,
        "source_language": detected_language,
        "target_language": language,
        "calories": final_calories,
        "nutrition": nutrition,
        "mode": mode,
        "summary": strip_html_tags(summary_source),
    }


def search_user_recipes(ingredients: str, limit: int = 8) -> List[Dict[str, Any]]:
    """Поиск рецептов пользователей по ингредиентам"""
    db = get_db()
    cur = db.cursor()
    
    # Разбиваем ингредиенты на отдельные слова для поиска
    ingredient_words = [word.strip().lower() for word in ingredients.split(",") if word.strip()]
    if not ingredient_words:
        return []
    
    # Создаем условия поиска: ищем в title, description или tags
    conditions = []
    params: List[Any] = []
    
    for word in ingredient_words:
        conditions.append(
            "(LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR LOWER(tags) LIKE ?)"
        )
        search_pattern = f"%{word}%"
        params.extend([search_pattern, search_pattern, search_pattern])
    
    # Используем OR для условий (хотя бы одно слово должно совпадать)
    where_clause = " OR ".join(conditions) if conditions else "1=1"
    where_clause = f"({where_clause}) AND status = 'published'"
    
    query = f"""
        SELECT * FROM community_posts 
        WHERE {where_clause}
        ORDER BY created_at DESC, likes DESC
        LIMIT ?
    """
    
    params.append(limit)
    cur.execute(query, params)
    rows = cur.fetchall()
    
    user_recipes = []
    for row in rows:
        video_url = row["video_url"]
        if row["video_local_path"]:
            video_url = build_upload_url(row["video_local_path"])
        thumbnail_url = row["thumbnail"]
        if row["thumbnail_local_path"]:
            thumbnail_url = build_upload_url(row["thumbnail_local_path"])
        
        # Извлекаем ингредиенты из description (простой парсинг)
        description = row["description"] or ""
        # Пытаемся найти ингредиенты в описании
        # Можно улучшить парсинг, но для начала используем описание как источник
        ingredients_list = []
        if description:
            # Простой парсинг: ищем слова, которые могут быть ингредиентами
            # В реальности можно использовать более сложный парсинг
            for word in ingredient_words:
                if word in description.lower():
                    ingredients_list.append(word.capitalize())
        
        # Если не нашли ингредиенты, используем теги
        if not ingredients_list:
            tags = deserialize_tags(row["tags"])
            ingredients_list = tags[:5]  # Берем первые 5 тегов как ингредиенты
        
        # Создаем шаги из описания
        steps = []
        if description:
            # Разбиваем описание на предложения как шаги
            sentences = re.split(r'[.!?]\s+', description)
            for idx, sentence in enumerate(sentences[:10], 1):  # Максимум 10 шагов
                if sentence.strip():
                    steps.append({
                        "number": idx,
                        "step": sentence.strip(),
                        "image": None
                    })
        
        # Если нет шагов, создаем один шаг из описания
        if not steps and description:
            steps = [{
                "number": 1,
                "step": description,
                "image": None
            }]
        
        recipe = {
            "id": f"user_{row['id']}",  # Префикс для отличия от Spoonacular
            "title": row["title"],
            "image": thumbnail_url or None,
            "source_image": thumbnail_url,
            "usedIngredientCount": len(ingredients_list),
            "ingredients": ingredients_list if ingredients_list else ["Рецепт пользователя"],
            "steps": steps,
            "instructions_raw": description,
            "video_url": video_url,
            "video_thumbnail": thumbnail_url,
            "author": row["author"],
            "author_avatar": row["avatar"],
            "source": "user",  # Помечаем как рецепт пользователя
            "summary": description[:200] if description else "",  # Первые 200 символов как summary
            "calories": None,  # Калории будут вычислены
            "nutrition": None,  # Nutrition будет вычислен
        }
        
        # Вычисляем калории и БЖУ для пользовательского рецепта
        nutrition_result, calculated_calories = ensure_nutrition_data(recipe)
        recipe["nutrition"] = nutrition_result
        recipe["calories"] = calculated_calories
        
        user_recipes.append(recipe)
    
    return user_recipes


def fetch_recommendations(
    limit: int = 8, tags: Optional[str] = None, include_ingredients: Optional[str] = None
) -> List[Dict[str, Any]]:
    url = "https://api.spoonacular.com/recipes/random"
    params = {
        "number": limit,
        "apiKey": SPOONACULAR_API_KEY,
        "sort": "random",
    }
    if tags:
        params["tags"] = tags
    if include_ingredients:
        params["includeIngredients"] = include_ingredients
    resp = requests.get(url, params=params, timeout=20)
    if resp.status_code != 200:
        return []
    data = resp.json()
    recipes = data.get("recipes", [])
    out = []
    for rec in recipes:
        item = {
            "id": rec.get("id"),
            "title": rec.get("title"),
            "image": build_proxy(rec.get("image")),
            "source_image": rec.get("image"),
            "ingredients": [
                i.get("original", "")
                for i in rec.get("extendedIngredients", [])
                if i.get("original")
            ],
            "steps": parse_steps(rec),
            "usedIngredientCount": rec.get("readyInMinutes") or 0,
            "instructions_raw": strip_html_tags(rec.get("instructions") or ""),
            "summary": rec.get("summary"),
        }
        out.append(item)
    return out


def decode_image_payload(image_base64: str) -> bytes:
    cleaned = image_base64.split(",")[-1]
    return base64.b64decode(cleaned)


def save_base64_file(
    payload: str,
    directory: Path,
    prefix: str,
    extension: str,
    subdir: str,
) -> str:
    cleaned = payload.split(",")[-1]
    data = base64.b64decode(cleaned)
    filename = f"{prefix}{uuid.uuid4().hex}{extension}"
    directory.mkdir(parents=True, exist_ok=True)
    filepath = directory / filename
    with open(filepath, "wb") as f:
        f.write(data)
    return f"{subdir}/{filename}"


def build_upload_url(relative_path: Optional[str]) -> Optional[str]:
    if not relative_path:
        return None
    base = "http://127.0.0.1:5000"
    if has_request_context():
        base = (request.host_url or base).rstrip("/")
    relative_path = relative_path.replace("\\", "/")
    return f"{base}/uploads/{relative_path}"


def analyze_image_with_spoonacular(image_bytes: bytes) -> Optional[Dict[str, Any]]:
    url = "https://api.spoonacular.com/food/images/analyze"
    files = {
        "file": ("capture.jpg", image_bytes, "image/jpeg"),
    }
    resp = requests.post(
        url,
        params={"apiKey": SPOONACULAR_API_KEY},
        files=files,
        timeout=40,
    )
    if resp.status_code != 200:
        return None
    return resp.json()


def build_analysis_response(raw: Dict[str, Any], language: str) -> Dict[str, Any]:
    nutrition = raw.get("nutrition", {})
    nutrients = nutrition.get("nutrients") or nutrition.get("nutrition", {}).get("nutrients", [])
    calories = None
    if isinstance(nutrients, list):
        for n in nutrients:
            if n.get("name", "").lower() == "calories":
                calories = n.get("amount")
                break
    confidence = raw.get("confidence")
    category = raw.get("category", {}) or {}
    recipes_raw = raw.get("recipes", []) or []
    recipes = []
    for rec in recipes_raw:
        image = rec.get("image")
        recipes.append(
            {
                "id": rec.get("id"),
                "title": translate_text(rec.get("title", ""), language),
                "image": build_proxy(image) if image else None,
                "source_image": image,
                "confidence": rec.get("confidence"),
            }
        )
    translated_label = translate_text(category.get("name", ""), language)
    return {
        "label": category.get("name"),
        "translated_label": translated_label,
        "confidence": confidence,
        "nutrition": nutrition,
        "calories": calories,
        "recipes": recipes,
    }


def deserialize_tags(value: Optional[str]) -> List[str]:
    if not value:
        return []
    try:
        data = json.loads(value)
        if isinstance(data, list):
            return [str(item) for item in data]
    except json.JSONDecodeError:
        pass
    return [t.strip() for t in value.split(",") if t.strip()]


def normalize_tags(value) -> List[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        return [part.strip() for part in value.split(",") if part.strip()]
    return []
def strip_html_tags(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"</(div|p|br|li|ul|ol|h[1-6])>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\s+\n", "\n", text)
    text = re.sub(r"\n\s+", "\n", text)
    return text.strip()


def parse_steps(info):
    analyzed = info.get("analyzedInstructions") or []
    steps_out = []
    if analyzed:
        for block in analyzed:
            for s in block.get("steps", []):
                txt = s.get("step", "")
                txt = strip_html_tags(txt)
                if txt:
                    steps_out.append({"number": s.get("number"), "step": txt, "image": None})
        return steps_out

    instr_raw = info.get("instructions") or ""
    if not instr_raw:
        return []
    li_matches = re.findall(r"<li[^>]*>(.*?)</li>", instr_raw, flags=re.IGNORECASE | re.DOTALL)
    if li_matches:
        for idx, li in enumerate(li_matches, 1):
            text = strip_html_tags(li)
            if text:
                steps_out.append({"number": idx, "step": text, "image": None})
        return steps_out

    plain = strip_html_tags(instr_raw)
    paras = [p.strip() for p in re.split(r"\n{1,}", plain) if p.strip()]
    if len(paras) > 1:
        for idx, p in enumerate(paras, 1):
            steps_out.append({"number": idx, "step": p, "image": None})
        return steps_out

    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", plain) if s.strip()]
    for idx, s in enumerate(sentences, 1):
        steps_out.append({"number": idx, "step": s, "image": None})
    return steps_out


def build_proxy(img_url):
    if not img_url:
        return None
    base = "http://127.0.0.1:5000"
    if has_request_context():
        base = (request.host_url or base).rstrip("/")
    return f"{base}/image_proxy?url={quote(img_url, safe='')}"


# ---------------- endpoints ----------------
@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "message": "RecipeApp API работает ✅",
        "translator": TRANSLATOR_AVAILABLE,
        "langdetect": LANGDETECT_AVAILABLE
    })


@app.route("/recipes", methods=["POST"])
def recipes():
    body = request.get_json(force=True, silent=True) or {}
    ingredients = (body.get("ingredients") or "").strip()
    if not ingredients:
        return jsonify({"recipes": [], "meta": {}})

    settings = get_user_settings()
    requested_mode = normalize_mode(body.get("mode") or settings["analysis_mode"])
    language = (body.get("language") or settings["language"] or DEFAULT_LANGUAGE).lower()
    filters = body.get("filters") or {}
    save_history = body.get("saveHistory", True)

    cache_key = json.dumps(
        {"ingredients": ingredients.lower(), "mode": requested_mode, "lang": language},
        ensure_ascii=False,
        sort_keys=True,
    )
    db = get_db()
    cur = db.cursor()
    now = int(time.time())

    cur.execute("SELECT json, ts FROM cached_recipes WHERE key = ?", (cache_key,))
    row = cur.fetchone()
    if row and now - row["ts"] < CACHE_TTL:
        data = json.loads(row["json"])
        # ВСЕГДА пересчитываем nutrition для всех рецептов из кэша, чтобы гарантировать наличие БЖУ
        for recipe in data:
            recipe_data = {
                **recipe,
                "ingredients": recipe.get("ingredients", []),
                "calories": recipe.get("calories"),
            }
            nutrition, calories = ensure_nutrition_data(recipe_data, recipe.get("nutrition"))
            recipe["nutrition"] = nutrition
            if calories:
                recipe["calories"] = calories
        if save_history:
            store_history_entry(ingredients, filters, requested_mode)
        return jsonify({"recipes": data, "meta": {"mode": requested_mode, "language": language}})

    search_url = "https://api.spoonacular.com/recipes/findByIngredients"
    params = {"ingredients": ingredients, "number": 8, "apiKey": SPOONACULAR_API_KEY}
    
    try:
        print(f"🌐 Запрос к Spoonacular API...")
        resp = requests.get(search_url, params=params, timeout=30)
        print(f"🌐 Spoonacular ответил: {resp.status_code}")
        
        if resp.status_code != 200:
            print(f"❌ Spoonacular вернул ошибку: {resp.text}")
            return jsonify({"error": "Spoonacular search failed", "details": resp.text}), 502
            
    except requests.exceptions.Timeout:
        print("❌ Таймаут при запросе к Spoonacular")
        return jsonify({"error": "Request timeout"}), 504
    except Exception as e:
        print(f"❌ Ошибка при запросе к Spoonacular: {e}")
        return jsonify({"error": f"Spoonacular API error: {str(e)}"}), 502

    list_recipes = resp.json() or []
    spoonacular_recipes = []
    for item in list_recipes:
        rid = item.get("id")
        title = item.get("title", "")
        image = item.get("image") or ""
        used_count = item.get("usedIngredientCount", 0)

        det_url = f"https://api.spoonacular.com/recipes/{rid}/information"
        try:
            dresp = requests.get(det_url, params={"apiKey": SPOONACULAR_API_KEY}, timeout=20)
        except Exception as e:
            print(f"⚠️ Не удалось получить детали рецепта {rid}: {e}")
            dresp = type('obj', (object,), {'status_code': 500})()
        ingredients_list: List[str] = []
        steps: List[Dict[str, Any]] = []
        instructions_raw = ""
        info = {}
        if dresp.status_code == 200:
            info = dresp.json()
            ext = info.get("extendedIngredients", []) or []
            ingredients_list = [
                i.get("original", "").strip() for i in ext if i.get("original")
            ]
            instructions_raw = info.get("instructions") or ""
            steps = parse_steps(info)
            if not image:
                image = info.get("image", "")

        recipe_payload = {
            "id": rid,
            "title": title,
            "image": build_proxy(image) if image else None,
            "source_image": image,
            "usedIngredientCount": used_count,
            "ingredients": ingredients_list,
            "steps": steps,
            "instructions_raw": instructions_raw,
            "source": "spoonacular",  # Помечаем как рецепт из Spoonacular
        }
        spoonacular_recipes.append(attach_recipe_metadata(recipe_payload, info, language, requested_mode))

    # Поиск рецептов пользователей
    print(f"🔍 Поиск рецептов пользователей для: '{ingredients}'")
    user_recipes_raw = search_user_recipes(ingredients, limit=8)
    user_recipes = []
    for recipe_data in user_recipes_raw:
        # Применяем метаданные (переводы и т.д.)
        user_recipes.append(attach_recipe_metadata(recipe_data, {}, language, requested_mode))

    # Объединяем результаты: 50% Spoonacular, 50% пользователи
    target_count = 8
    max_spoon = len(spoonacular_recipes)
    max_user = len(user_recipes)
    
    # Вычисляем сколько брать от каждого источника (50/50)
    half_count = target_count // 2
    spoon_count = min(half_count, max_spoon)
    user_count = min(half_count, max_user)
    
    # Если одного источника не хватает, дополняем другим
    total_so_far = spoon_count + user_count
    if total_so_far < target_count:
        remaining = target_count - total_so_far
        if spoon_count < max_spoon:
            # Дополняем Spoonacular
            add_spoon = min(remaining, max_spoon - spoon_count)
            spoon_count += add_spoon
            remaining -= add_spoon
        if remaining > 0 and user_count < max_user:
            # Дополняем пользовательскими
            user_count += min(remaining, max_user - user_count)
    
    # Чередуем результаты для равномерного распределения
    combined = []
    max_iter = max(spoon_count, user_count)
    for i in range(max_iter):
        # Добавляем по одному от каждого источника по очереди
        if i < spoon_count and i < len(spoonacular_recipes):
            combined.append(spoonacular_recipes[i])
        if i < user_count and i < len(user_recipes):
            combined.append(user_recipes[i])
        # Останавливаемся если достигли целевого количества
        if len(combined) >= target_count:
            break
    
    # Если все еще не хватило, добавляем оставшиеся
    if len(combined) < target_count:
        # Сначала добавляем оставшиеся Spoonacular
        for recipe in spoonacular_recipes[spoon_count:]:
            if len(combined) >= target_count:
                break
            combined.append(recipe)
        # Затем оставшиеся пользовательские
        for recipe in user_recipes[user_count:]:
            if len(combined) >= target_count:
                break
            combined.append(recipe)

    out = combined[:target_count]  # Ограничиваем до нужного количества
    
    # Убеждаемся, что все рецепты имеют nutrition данные
    for recipe in out:
        recipe_id = recipe.get("id", "unknown")
        # Всегда пересчитываем nutrition для гарантии наличия данных
        recipe_data = {
            **recipe,
            "ingredients": recipe.get("ingredients", []),
            "calories": recipe.get("calories"),
        }
        nutrition, calories = ensure_nutrition_data(recipe_data, recipe.get("nutrition"))
        recipe["nutrition"] = nutrition
        if calories:
            recipe["calories"] = calories
        
        # Отладочный вывод для проверки
        print(f"🔍 Recipe {recipe_id} nutrition: {json.dumps(nutrition, indent=2)}")

    cur.execute(
        "REPLACE INTO cached_recipes (key, json, ts) VALUES (?, ?, ?)",
        (cache_key, json.dumps(out, ensure_ascii=False), now),
    )
    db.commit()
    if save_history:
        store_history_entry(ingredients, filters, requested_mode)
    return jsonify({"recipes": out, "meta": {"mode": requested_mode, "language": language}})


# favorites
@app.route("/favorites", methods=["GET"])
def get_favorites():
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT recipe_id, json FROM favorites ORDER BY ts DESC")
    rows = cur.fetchall()
    favs = [json.loads(r["json"]) for r in rows]
    return jsonify({"favorites": favs})


@app.route("/favorites", methods=["POST"])
def add_favorite():
    body = request.get_json(force=True, silent=True) or {}
    recipe = body.get("recipe")
    if not recipe:
        return jsonify({"error": "no recipe"}), 400
    rid = recipe.get("id")
    if rid is None:
        return jsonify({"error": "recipe has no id"}), 400
    db = get_db()
    cur = db.cursor()
    now = int(time.time())
    cur.execute("REPLACE INTO favorites (recipe_id, json, ts) VALUES (?, ?, ?)", (rid, json.dumps(recipe, ensure_ascii=False), now))
    db.commit()
    return jsonify({"ok": True})


@app.route("/favorites/<int:rid>", methods=["DELETE"])
def remove_favorite(rid):
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM favorites WHERE recipe_id = ?", (rid,))
    db.commit()
    return jsonify({"ok": True})


# image proxy
@app.route("/image_proxy", methods=["GET"])
def image_proxy():
    url = request.args.get("url", "")
    if not url:
        return jsonify({"error": "no url"}), 400
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return jsonify({"error": "invalid url"}), 400
    try:
        resp = requests.get(url, stream=True, timeout=20, headers={"User-Agent": "RecipeApp/1.0"})
        if resp.status_code != 200:
            return jsonify({"error": f"failed to fetch image {resp.status_code}"}), 502
        content_type = resp.headers.get("Content-Type", "image/jpeg")
        return Response(resp.content, content_type=content_type)
    except Exception as e:
        return jsonify({"error": f"image proxy error: {str(e)}"}), 500


@app.route("/history", methods=["GET", "DELETE"])
def history():
    if request.method == "GET":
        limit = min(int(request.args.get("limit", 25)), 100)
        return jsonify({"history": get_history(limit)})
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM search_history")
    db.commit()
    return jsonify({"ok": True})


@app.route("/settings", methods=["GET", "POST"])
def settings():
    if request.method == "GET":
        return jsonify(get_user_settings())
    body = request.get_json(force=True, silent=True) or {}
    updated = update_user_settings(body.get("analysis_mode"), body.get("language"))
    return jsonify(updated)


def _process_single_recipe(rec: Dict[str, Any], language: str, mode: str) -> Dict[str, Any]:
    """Обработка одного рецепта с переводами и nutrition данными"""
    ingredients_list = rec.get("ingredients", [])
    steps = rec.get("steps", [])
    summary_source = rec.get("summary", "")
    
    detected_language = detect_language_safe(rec.get("title", "")) or language
    needs_translation = language and detected_language != language
    
    translated_title = rec.get("title")
    translated_ingredients = ingredients_list
    translated_steps = steps
    
    if needs_translation:
        translated_title = translate_text(rec.get("title", ""), language)
        translated_ingredients = translate_list(ingredients_list, language)
        translated_steps = translate_steps(steps, language)
    
    # Загружаем nutrition данные
    nutrition = None
    calories = None
    recipe_id = rec.get("id")
    if recipe_id:
        try:
            nutrition = fetch_nutrition(recipe_id)
            calories = extract_calories(nutrition)
        except Exception as e:
            print(f"Ошибка при загрузке nutrition для рецепта {recipe_id}: {e}")
            nutrition = None
            calories = None
    
    # Создаем объект рецепта для ensure_nutrition_data
    recipe_data = {
        **rec,
        "ingredients": ingredients_list,
        "calories": calories,
    }
    
    # Обеспечиваем наличие калорий и БЖУ в nutrition
    print(f"🔍 _process_single_recipe для рецепта {recipe_id}: вызываем ensure_nutrition_data")
    nutrition, final_calories = ensure_nutrition_data(recipe_data, nutrition)
    print(f"✅ _process_single_recipe для рецепта {recipe_id}: nutrition keys={list(nutrition.keys()) if nutrition else 'None'}, protein={nutrition.get('protein') if nutrition else None}, fat={nutrition.get('fat') if nutrition else None}, carbs={nutrition.get('carbs') if nutrition else None}")
    
    return {
        **rec,
        "ingredients": ingredients_list,
        "steps": steps,
        "translated_title": translated_title,
        "translated_ingredients": translated_ingredients,
        "translated_steps": translated_steps,
        "source_language": detected_language,
        "target_language": language,
        "calories": final_calories,
        "nutrition": nutrition,
        "mode": mode,
        "summary": strip_html_tags(summary_source),
    }


@app.route("/recommendations", methods=["GET"])
def recommendations():
    limit = min(int(request.args.get("limit", 6)), 20)
    settings = get_user_settings()
    language = (request.args.get("language") or settings["language"]).lower()
    mode = normalize_mode(request.args.get("mode") or settings["analysis_mode"])
    tags = request.args.get("tags")
    ingredients = request.args.get("ingredients")
    
    # Проверяем кэш для рекомендаций
    cache_key = json.dumps({
        "limit": limit,
        "tags": tags or "",
        "ingredients": ingredients or "",
        "language": language,
        "mode": mode
    }, sort_keys=True)
    
    db = get_db()
    cur = db.cursor()
    now = int(time.time())
    
    # Проверяем кэш (используем cached_recipes таблицу)
    cur.execute("SELECT json, ts FROM cached_recipes WHERE key = ?", (cache_key,))
    row = cur.fetchone()
    if row and now - row["ts"] < RECOMMENDATIONS_CACHE_TTL:
        # Возвращаем из кэша, но ВСЕГДА пересчитываем nutrition для гарантии наличия БЖУ
        print(f"🔍 Loading from cache, but recalculating nutrition for {len(cached_data.get('recipes', []))} recipes")
        cached_data = json.loads(row["json"])
        recipes = cached_data.get("recipes", [])
        for recipe in recipes:
            recipe_id = recipe.get("id", "unknown")
            print(f"🔍 Processing cached recipe {recipe_id}")
            recipe_data = {
                **recipe,
                "ingredients": recipe.get("ingredients", []),
                "calories": recipe.get("calories"),
            }
            nutrition, calories = ensure_nutrition_data(recipe_data, recipe.get("nutrition"))
            recipe["nutrition"] = nutrition
            if calories:
                recipe["calories"] = calories
            print(f"✅ Recipe {recipe_id} nutrition updated: protein={nutrition.get('protein')}, fat={nutrition.get('fat')}, carbs={nutrition.get('carbs')}")
        return jsonify({"recipes": recipes, "meta": cached_data["meta"]})
    
    # Если кэша нет или он устарел, делаем запрос
    recs = fetch_recommendations(limit, tags, ingredients)
    
    # Параллельная обработка рецептов для ускорения загрузки
    enriched = []
    with ThreadPoolExecutor(max_workers=min(len(recs), 8)) as executor:
        future_to_recipe = {
            executor.submit(_process_single_recipe, rec, language, mode): rec
            for rec in recs
        }
        for future in as_completed(future_to_recipe):
            try:
                enriched.append(future.result())
            except Exception as e:
                print(f"Ошибка при обработке рецепта: {e}")
                # В случае ошибки добавляем рецепт без переводов, но с вычисленными калориями и БЖУ
                rec = future_to_recipe[future]
                recipe_data = {
                    **rec,
                    "ingredients": rec.get("ingredients", []),
                    "calories": None,
                }
                # Вычисляем калории и БЖУ даже при ошибке
                nutrition, calculated_calories = ensure_nutrition_data(recipe_data)
                enriched.append({
                    **rec,
                    "translated_title": rec.get("title"),
                    "translated_ingredients": rec.get("ingredients", []),
                    "translated_steps": rec.get("steps", []),
                    "source_language": language,
                    "target_language": language,
                    "calories": calculated_calories,
                    "nutrition": nutrition,
                    "mode": mode,
                    "summary": strip_html_tags(rec.get("summary", "")),
                })
    
    # Сохраняем порядок рецептов
    enriched.sort(key=lambda x: next((i for i, r in enumerate(recs) if r.get("id") == x.get("id")), 0))
    
    # Убеждаемся, что все рецепты имеют nutrition данные
    print(f"🔍 Final check: ensuring nutrition for {len(enriched)} recipes")
    for recipe in enriched:
        recipe_id = recipe.get("id", "unknown")
        print(f"🔍 Final check for recipe {recipe_id}")
        recipe_data = {
            **recipe,
            "ingredients": recipe.get("ingredients", []),
            "calories": recipe.get("calories"),
        }
        nutrition, calories = ensure_nutrition_data(recipe_data, recipe.get("nutrition"))
        recipe["nutrition"] = nutrition
        if calories:
            recipe["calories"] = calories
        print(f"✅ Final check recipe {recipe_id}: protein={nutrition.get('protein')}, fat={nutrition.get('fat')}, carbs={nutrition.get('carbs')}")
    
    result = {
        "recipes": enriched,
        "meta": {"mode": mode, "language": language}
    }
    
    # Сохраняем в кэш
    cur.execute(
        "REPLACE INTO cached_recipes (key, json, ts) VALUES (?, ?, ?)",
        (cache_key, json.dumps(result, ensure_ascii=False), now)
    )
    db.commit()
    
    return jsonify(result)


@app.route("/analyze", methods=["POST"])
def analyze():
    body = request.get_json(force=True, silent=True) or {}
    image_base64 = body.get("image_base64")
    image_url = body.get("image_url")
    if not image_base64 and not image_url:
        return jsonify({"error": "image_base64 or image_url required"}), 400

    settings = get_user_settings()
    language = (body.get("language") or settings["language"] or DEFAULT_LANGUAGE).lower()
    mode = normalize_mode(body.get("mode") or settings["analysis_mode"])

    raw = None
    if image_base64:
        try:
            image_bytes = decode_image_payload(image_base64)
        except Exception as exc:
            return jsonify({"error": f"invalid base64 payload: {exc}"}), 400
        raw = analyze_image_with_spoonacular(image_bytes)
    else:
        url = "https://api.spoonacular.com/food/images/analyze"
        resp = requests.post(
            url,
            params={"apiKey": SPOONACULAR_API_KEY},
            data={"imageUrl": image_url},
            timeout=40,
        )
        if resp.status_code == 200:
            raw = resp.json()

    if not raw:
        return jsonify({"error": "analysis failed"}), 502

    analysis = build_analysis_response(raw, language)
    return jsonify({"analysis": analysis, "mode": mode, "language": language})


@app.route("/translate", methods=["POST"])
def translate_endpoint():
    body = request.get_json(force=True, silent=True) or {}
    text = body.get("text", "")
    language = (body.get("language") or DEFAULT_LANGUAGE).lower()
    translated = translate_text(text, language)
    return jsonify({"original": text, "translated": translated, "language": language})


@app.route("/uploads/<path:filename>", methods=["GET"])
def serve_upload(filename):
    try:
        full_path = (UPLOAD_DIR / filename).resolve()
        uploads_root = UPLOAD_DIR.resolve()
        if not str(full_path).startswith(str(uploads_root)):
            raise ValueError("outside upload dir")
    except Exception:
        abort(404)
    relative = os.path.relpath(full_path, uploads_root)
    return send_from_directory(str(uploads_root), relative)


def community_row_to_dict(row) -> Dict[str, Any]:
    video_url = row["video_url"]
    if row["video_local_path"]:
        video_url = build_upload_url(row["video_local_path"])
    thumbnail_url = row["thumbnail"]
    if row["thumbnail_local_path"]:
        thumbnail_url = build_upload_url(row["thumbnail_local_path"])
    return {
        "id": row["id"],
        "title": row["title"],
        "author": row["author"],
        "avatar": row["avatar"],
        "description": row["description"],
        "video_url": video_url,
        "thumbnail": thumbnail_url,
        "likes": row["likes"],
        "tags": deserialize_tags(row["tags"]),
        "created_at": row["created_at"],
        "status": row["status"],
    }


@app.route("/community", methods=["GET"])
def community_feed():
    tag = request.args.get("tag")
    limit = min(int(request.args.get("limit", 10)), 30)
    include_pending = request.args.get("include_pending") == "1"
    db = get_db()
    cur = db.cursor()
    clauses = []
    params: List[Any] = []
    if not include_pending:
        clauses.append("status = 'published'")
    if tag:
        clauses.append("lower(tags) LIKE ?")
        params.append(f"%{tag.lower()}%")
    where_sql = ""
    if clauses:
        where_sql = "WHERE " + " AND ".join(clauses)
    params.append(limit)
    cur.execute(
        f"SELECT * FROM community_posts {where_sql} ORDER BY created_at DESC LIMIT ?",
        params,
    )
    rows = cur.fetchall()
    return jsonify({"videos": [community_row_to_dict(row) for row in rows]})


@app.route("/community/<int:cid>/like", methods=["POST"])
def community_like(cid):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE community_posts SET likes = likes + 1 WHERE id = ?",
        (cid,),
    )
    if cur.rowcount == 0:
        return jsonify({"error": "post not found"}), 404
    db.commit()
    cur.execute("SELECT likes FROM community_posts WHERE id = ?", (cid,))
    likes = cur.fetchone()["likes"]
    return jsonify({"id": cid, "likes": likes})


@app.route("/community", methods=["POST"])
def community_create():
    body = request.get_json(force=True, silent=True) or {}
    title = (body.get("title") or "").strip()
    author = (body.get("author") or "").strip()
    description = (body.get("description") or "").strip()
    avatar = (body.get("avatar") or "").strip() or None
    tags = normalize_tags(body.get("tags"))
    status = (body.get("status") or "pending").strip().lower()
    if status not in {"pending", "published", "rejected"}:
        status = "pending"
    if not title or not author:
        return jsonify({"error": "title and author are required"}), 400
    video_url = body.get("video_url")
    video_local_path = None
    video_base64 = body.get("video_base64")
    if video_base64:
        video_local_path = save_base64_file(
            video_base64, VIDEOS_DIR, "video_", ".mp4", "videos"
        )
        video_url = build_upload_url(video_local_path)
    # video_url теперь опциональный - рецепты могут быть без видео
    thumb_url = body.get("thumbnail_url")
    thumb_local_path = None
    thumb_base64 = body.get("thumbnail_base64")
    if thumb_base64:
        thumb_local_path = save_base64_file(
            thumb_base64, THUMBS_DIR, "thumb_", ".jpg", "thumbnails"
        )
        thumb_url = build_upload_url(thumb_local_path)
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    INSERT INTO community_posts
    (title, author, avatar, description, video_url, video_local_path,
     thumbnail, thumbnail_local_path, likes, tags, created_at, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
    """,
        (
            title,
            author,
            avatar,
            description,
            video_url,
            video_local_path,
            thumb_url,
            thumb_local_path,
            json.dumps(tags, ensure_ascii=False),
            int(time.time()),
            status,
        ),
    )
    db.commit()
    new_id = cur.lastrowid
    cur.execute("SELECT * FROM community_posts WHERE id = ?", (new_id,))
    row = cur.fetchone()
    return jsonify({"video": community_row_to_dict(row)})


@app.route("/community/<int:cid>/status", methods=["POST"])
def community_update_status(cid):
    body = request.get_json(force=True, silent=True) or {}
    status = (body.get("status") or "").strip().lower()
    if status not in {"pending", "published", "rejected"}:
        return jsonify({"error": "invalid status"}), 400
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE community_posts SET status = ? WHERE id = ?",
        (status, cid),
    )
    if cur.rowcount == 0:
        return jsonify({"error": "post not found"}), 404
    db.commit()
    cur.execute("SELECT * FROM community_posts WHERE id = ?", (cid,))
    row = cur.fetchone()
    return jsonify({"video": community_row_to_dict(row)})


# Комментарии к рецептам
@app.route("/recipes/<recipe_id>/comments", methods=["GET", "POST"])
def recipe_comments(recipe_id):
    db = get_db()
    cur = db.cursor()
    
    if request.method == "GET":
        limit = min(int(request.args.get("limit", 50)), 100)
        cur.execute(
            """
        SELECT * FROM recipe_comments
        WHERE recipe_id = ? AND status = 'published'
        ORDER BY created_at DESC
        LIMIT ?
        """,
            (recipe_id, limit),
        )
        rows = cur.fetchall()
        comments = []
        for row in rows:
            comments.append({
                "id": row["id"],
                "recipe_id": row["recipe_id"],
                "author": row["author"],
                "author_avatar": row["author_avatar"],
                "text": row["text"],
                "created_at": row["created_at"],
            })
        return jsonify({"comments": comments})
    
    # POST - добавить комментарий
    body = request.get_json(force=True, silent=True) or {}
    author = (body.get("author") or "").strip()
    text = (body.get("text") or "").strip()
    author_avatar = body.get("author_avatar")
    
    if not author or not text:
        return jsonify({"error": "author and text are required"}), 400
    
    cur.execute(
        """
    INSERT INTO recipe_comments
    (recipe_id, author, author_avatar, text, created_at, status)
    VALUES (?, ?, ?, ?, ?, 'published')
    """,
        (recipe_id, author, author_avatar, text, int(time.time())),
    )
    db.commit()
    new_id = cur.lastrowid
    cur.execute("SELECT * FROM recipe_comments WHERE id = ?", (new_id,))
    row = cur.fetchone()
    return jsonify({
        "comment": {
            "id": row["id"],
            "recipe_id": row["recipe_id"],
            "author": row["author"],
            "author_avatar": row["author_avatar"],
            "text": row["text"],
            "created_at": row["created_at"],
        }
    })


# Подписки на авторов
@app.route("/authors/<author>/subscribe", methods=["POST", "DELETE"])
def author_subscribe(author):
    body = request.get_json(force=True, silent=True) or {}
    subscriber = (body.get("subscriber") or "").strip()
    
    if not subscriber:
        return jsonify({"error": "subscriber is required"}), 400
    
    db = get_db()
    cur = db.cursor()
    
    if request.method == "POST":
        # Подписаться
        try:
            cur.execute(
                """
            INSERT INTO author_subscriptions (subscriber, author, created_at)
            VALUES (?, ?, ?)
            """,
                (subscriber, author, int(time.time())),
            )
            db.commit()
            return jsonify({"ok": True, "subscribed": True})
        except sqlite3.IntegrityError:
            # Уже подписан
            return jsonify({"ok": True, "subscribed": True})
    
    # DELETE - отписаться
    # Для DELETE берем subscriber из query параметров или body
    if request.method == "DELETE":
        subscriber = request.args.get("subscriber") or body.get("subscriber") or ""
        if not subscriber:
            return jsonify({"error": "subscriber is required"}), 400
    
    cur.execute(
        "DELETE FROM author_subscriptions WHERE subscriber = ? AND author = ?",
        (subscriber, author),
    )
    db.commit()
    return jsonify({"ok": True, "subscribed": False})


@app.route("/authors/<author>/subscribers", methods=["GET"])
def author_subscribers(author):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT COUNT(*) as cnt FROM author_subscriptions WHERE author = ?",
        (author,),
    )
    count = cur.fetchone()["cnt"]
    return jsonify({"author": author, "subscribers_count": count})


@app.route("/subscribers/<subscriber>/subscriptions", methods=["GET"])
def user_subscriptions(subscriber):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        """
    SELECT author FROM author_subscriptions
    WHERE subscriber = ?
    ORDER BY created_at DESC
    """,
        (subscriber,),
    )
    rows = cur.fetchall()
    authors = [row["author"] for row in rows]
    return jsonify({"subscriber": subscriber, "subscriptions": authors})


@app.route("/subscribers/<subscriber>/is_subscribed/<author>", methods=["GET"])
def is_subscribed(subscriber, author):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT COUNT(*) as cnt FROM author_subscriptions WHERE subscriber = ? AND author = ?",
        (subscriber, author),
    )
    count = cur.fetchone()["cnt"]
    return jsonify({"subscribed": count > 0})


# ---------------- init ----------------
if __name__ == "__main__":
    print("🚀 Запуск RecipeApp...")
    with app.app_context():
        init_db()
    print("✅ База данных инициализирована")
    print("🌐 Запуск сервера на http://127.0.0.1:5000")
    if not TRANSLATOR_AVAILABLE:
        print("ℹ️  Переводы отключены (googletrans не установлен)")
    app.run(debug=True, host="127.0.0.1", port=5000)
