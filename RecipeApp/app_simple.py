# app_simple.py - упрощенная версия без переводов
import base64
import json
import os
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional
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

# ---------------- config ----------------
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
            video_url TEXT NOT NULL,
            thumbnail TEXT,
            video_local_path TEXT,
            thumbnail_local_path TEXT,
            likes INTEGER DEFAULT 0,
            tags TEXT,
            created_at INTEGER NOT NULL,
            status TEXT DEFAULT 'published'
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
def normalize_mode(raw: Optional[str]) -> str:
    if not raw:
        return DEFAULT_MODE
    value = raw.strip().lower()
    if value not in ALLOWED_MODES:
        return DEFAULT_MODE
    return value

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
    # Ограничиваем количество записей
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

def build_upload_url(relative_path: Optional[str]) -> Optional[str]:
    if not relative_path:
        return None
    base = "http://127.0.0.1:5000"
    if has_request_context():
        base = (request.host_url or base).rstrip("/")
    relative_path = relative_path.replace("\\", "/")
    return f"{base}/uploads/{relative_path}"

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

# ---------------- endpoints ----------------
@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "message": "RecipeApp API работает ✅",
        "translator": False,
        "version": "simple"
    })

@app.route("/recipes", methods=["POST"])
def recipes():
    print("🔍 Получен запрос на поиск рецептов")
    body = request.get_json(force=True, silent=True) or {}
    ingredients = (body.get("ingredients") or "").strip()
    if not ingredients:
        return jsonify({"recipes": [], "meta": {}})

    settings = get_user_settings()
    requested_mode = normalize_mode(body.get("mode") or settings["analysis_mode"])
    language = (body.get("language") or settings["language"] or DEFAULT_LANGUAGE).lower()

    print(f"🔍 Поиск: '{ingredients}' в режиме '{requested_mode}'")

    cache_key = json.dumps(
        {"ingredients": ingredients.lower(), "mode": requested_mode, "lang": language},
        ensure_ascii=False,
        sort_keys=True,
    )
    db = get_db()
    cur = db.cursor()
    now = int(time.time())

    # Проверяем кэш
    cur.execute("SELECT json, ts FROM cached_recipes WHERE key = ?", (cache_key,))
    row = cur.fetchone()
    if row and now - row["ts"] < CACHE_TTL:
        data = json.loads(row["json"])
        store_history_entry(ingredients, None, requested_mode)
        print(f"✅ Возвращен кэшированный результат: {len(data)} рецептов")
        return jsonify({"recipes": data, "meta": {"mode": requested_mode, "language": language}})

    # Запрос к Spoonacular API
    search_url = "https://api.spoonacular.com/recipes/findByIngredients"
    params = {"ingredients": ingredients, "number": 8, "apiKey": SPOONACULAR_API_KEY}

    try:
        print("🌐 Запрос к Spoonacular API...")
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
    print(f"📋 Найдено рецептов: {len(list_recipes)}")

    out = []
    for i, item in enumerate(list_recipes):
        rid = item.get("id")
        title = item.get("title", "")
        image = item.get("image") or ""

        print(f"📖 Обработка рецепта {i+1}/{len(list_recipes)}: {title}")

        # Получаем детальную информацию о рецепте
        det_url = f"https://api.spoonacular.com/recipes/{rid}/information"
        ingredients_list: List[str] = []
        steps: List[Dict[str, Any]] = []

        try:
            dresp = requests.get(det_url, params={"apiKey": SPOONACULAR_API_KEY}, timeout=20)
            if dresp.status_code == 200:
                info = dresp.json()
                ext = info.get("extendedIngredients", []) or []
                ingredients_list = [
                    i.get("original", "").strip() for i in ext if i.get("original")
                ]
                steps = parse_steps(info)
                if not image:
                    image = info.get("image", "")
        except Exception as e:
            print(f"⚠️ Не удалось получить детали рецепта {rid}: {e}")

        recipe_payload = {
            "id": rid,
            "title": title,
            "image": build_proxy(image) if image else None,
            "source_image": image,
            "usedIngredientCount": item.get("usedIngredientCount", 0),
            "ingredients": ingredients_list,
            "steps": steps,
            "instructions_raw": "",
            # Без переводов в упрощенной версии
            "translated_title": title,
            "translated_ingredients": ingredients_list,
            "translated_steps": steps,
        }
        out.append(recipe_payload)

    # Сохраняем в кэш
    cur.execute(
        "REPLACE INTO cached_recipes (key, json, ts) VALUES (?, ?, ?)",
        (cache_key, json.dumps(out, ensure_ascii=False), now),
    )
    db.commit()
    store_history_entry(ingredients, None, requested_mode)

    print(f"✅ Возвращено {len(out)} рецептов")
    return jsonify({"recipes": out, "meta": {"mode": requested_mode, "language": language}})

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
        return jsonify({"history": history})
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
    current = get_user_settings()
    new_mode = normalize_mode(body.get("analysis_mode") or current["analysis_mode"])
    new_language = (body.get("language") or current["language"] or DEFAULT_LANGUAGE).lower()
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
    return jsonify({"analysis_mode": new_mode, "language": new_language})

@app.route("/recommendations", methods=["GET"])
def recommendations():
    limit = min(int(request.args.get("limit", 6)), 20)
    settings = get_user_settings()
    language = (request.args.get("language") or settings["language"]).lower()
    mode = normalize_mode(request.args.get("mode") or settings["analysis_mode"])
    tags = request.args.get("tags")
    
    url = "https://api.spoonacular.com/recipes/random"
    params = {
        "number": limit,
        "apiKey": SPOONACULAR_API_KEY,
        "sort": "random",
    }
    if tags:
        params["tags"] = tags
    
    try:
        resp = requests.get(url, params=params, timeout=20)
        if resp.status_code != 200:
            return jsonify({"recipes": [], "meta": {"mode": mode, "language": language}})
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
                "translated_title": rec.get("title"),
                "translated_ingredients": [
                    i.get("original", "")
                    for i in rec.get("extendedIngredients", [])
                    if i.get("original")
                ],
                "translated_steps": parse_steps(rec),
            }
            out.append(item)
        return jsonify({"recipes": out, "meta": {"mode": mode, "language": language}})
    except Exception as e:
        print(f"Error fetching recommendations: {e}")
        return jsonify({"recipes": [], "meta": {"mode": mode, "language": language}})

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
            cleaned = image_base64.split(",")[-1]
            image_bytes = base64.b64decode(cleaned)
        except Exception as exc:
            return jsonify({"error": f"invalid base64 payload: {exc}"}), 400
        
        url = "https://api.spoonacular.com/food/images/analyze"
        files = {
            "file": ("capture.jpg", image_bytes, "image/jpeg"),
        }
        try:
            resp = requests.post(
                url,
                params={"apiKey": SPOONACULAR_API_KEY},
                files=files,
                timeout=40,
            )
            if resp.status_code == 200:
                raw = resp.json()
        except Exception as e:
            return jsonify({"error": f"analysis failed: {str(e)}"}), 502
    else:
        url = "https://api.spoonacular.com/food/images/analyze"
        try:
            resp = requests.post(
                url,
                params={"apiKey": SPOONACULAR_API_KEY},
                data={"imageUrl": image_url},
                timeout=40,
            )
            if resp.status_code == 200:
                raw = resp.json()
        except Exception as e:
            return jsonify({"error": f"analysis failed: {str(e)}"}), 502

    if not raw:
        return jsonify({"error": "analysis failed"}), 502

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
                "title": rec.get("title", ""),
                "image": build_proxy(image) if image else None,
                "source_image": image,
                "confidence": rec.get("confidence"),
            }
        )
    
    analysis = {
        "label": category.get("name"),
        "translated_label": category.get("name"),
        "confidence": confidence,
        "nutrition": nutrition,
        "calories": calories,
        "recipes": recipes,
    }
    return jsonify({"analysis": analysis, "mode": mode, "language": language})

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
    if not video_url:
        return jsonify({"error": "video_url or video_base64 required"}), 400
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

# ---------------- init ----------------
if __name__ == "__main__":
    print("🚀 Запуск RecipeApp (упрощенная версия)...")
    with app.app_context():
        init_db()
    print("✅ База данных инициализирована")
    print("🌐 Запуск сервера на http://127.0.0.1:5000")
    print("ℹ️  Переводы отключены (googletrans не установлен)")
    app.run(debug=True, host="127.0.0.1", port=5000)

