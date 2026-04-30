# Полное ТЗ: Профили и Система Сообществ H.A.N. Eat

**Версия:** 1.0  
**Дата:** 2025-01-XX  
**Статус:** Готово к реализации

---

## Содержание

1. [Обзор системы](#1-обзор-системы)
2. [Архитектура](#2-архитектура)
3. [API Спецификация](#3-api-спецификация)
4. [Схема БД](#4-схема-бд)
5. [UI/UX Структура](#5-uiux-структура)
6. [Алгоритмы и Логика](#6-алгоритмы-и-логика)
7. [Модерация](#7-модерация)
8. [Медиа Обработка](#8-медиа-обработка)
9. [Масштабирование](#9-масштабирование)
10. [Списки задач](#10-списки-задач)

---

## 1. Обзор системы

### 1.1 Цель
Создать гибридную социальную платформу (VK + Instagram) с фокусом на рецепты и короткие видео (рилсы), включающую:
- Профили пользователей с контентом
- Систему сообществ
- Ленту с персонализацией
- Модерацию контента
- Монетизацию (H.A.N. Plus)

### 1.2 Ключевые фичи

#### Профиль пользователя
- Аватар, имя, bio, статистика
- Вкладки: Posts, Reels, Saved
- Настройки приватности
- Подписчики/подписки

#### Публикации
- Типы: текст, фото, рецепт, короткое видео (Reel)
- Лайки, комментарии, репосты, сохранение
- Публикация в сообщества

#### Рилсы
- Вертикальные короткие видео (до 2 мин)
- Автоплей в ленте
- Метрики: просмотры, лайки, комментарии

#### Сообщества
- Страницы сообществ с обложкой
- Публикации от сообщества
- Администраторы и модераторы
- Автоматическое распространение контента

#### Лента
- Персональная лента (подписки + рекомендации)
- Reels feed (вертикальная прокрутка)
- Алгоритм ранжирования

---

## 2. Архитектура

### 2.1 Общая архитектура

```
┌─────────────────┐
│   Mobile App    │ (Flutter)
│   (Flutter)     │
└────────┬────────┘
         │ HTTPS/REST
         │
┌────────▼─────────────────────────────────────┐
│         API Gateway (FastAPI/NestJS)        │
│  - Auth, Rate Limiting, Routing             │
└────────┬─────────────────────────────────────┘
         │
    ┌────┴────┬──────────┬──────────┬──────────┐
    │         │          │          │          │
┌───▼───┐ ┌──▼───┐ ┌────▼────┐ ┌──▼───┐ ┌───▼────┐
│ Auth  │ │Posts │ │ Feed    │ │Media │ │Moder-  │
│Service│ │Service│ │Service  │ │Service│ │ation  │
└───┬───┘ └──┬───┘ └────┬────┘ └──┬───┘ └───┬────┘
    │        │          │          │          │
┌───▼────────▼──────────▼──────────▼──────────▼───┐
│         PostgreSQL (Primary + Replicas)        │
└────────────────────────────────────────────────┘
         │
┌────────▼────────┐    ┌──────────▼──────────┐
│   Redis Cache   │    │  S3/Object Storage  │
│  (Feed, Counters)│    │   (Media Files)     │
└─────────────────┘    └─────────────────────┘
         │
┌────────▼────────┐
│  Queue (RabbitMQ│
│  /Redis Streams) │
│  - Transcoding   │
│  - Notifications │
└─────────────────┘
```

### 2.2 Компоненты

#### Backend Services
1. **Auth Service** - аутентификация, JWT, OAuth
2. **Posts Service** - CRUD постов, рецептов, рилсов
3. **Feed Service** - генерация ленты, ранжирование
4. **Media Service** - загрузка, обработка, CDN
5. **Moderation Service** - авто-модерация, ручная проверка
6. **Analytics Service** - сбор метрик, события
7. **Notification Service** - push, email уведомления

#### Infrastructure
- **PostgreSQL** - основная БД (primary + read replicas)
- **Redis** - кэш лент, счетчики, rate limiting
- **S3-compatible Storage** - медиа файлы
- **CDN** - Cloudflare/CloudFront для раздачи медиа
- **Queue** - RabbitMQ/Redis Streams для фоновых задач
- **Workers** - FFmpeg для транс-кодинга видео

### 2.3 Технологический стек

**Backend:**
- Python (FastAPI) или Node.js (NestJS)
- PostgreSQL 14+
- Redis 7+
- RabbitMQ / Redis Streams

**Frontend:**
- Flutter (Dart)
- Material Design 3

**Infrastructure:**
- Docker + Kubernetes (или managed services)
- AWS S3 / DigitalOcean Spaces
- Cloudflare CDN
- Prometheus + Grafana (мониторинг)

---

## 3. API Спецификация

### 3.1 Базовый URL
```
Production: https://api.haneat.com/api/v1
Development: http://localhost:5000/api/v1
```

### 3.2 Аутентификация

Все защищенные endpoints требуют Bearer token в заголовке:
```
Authorization: Bearer <jwt_token>
```

#### Endpoints

**POST /auth/register**
```json
Request:
{
  "email": "user@example.com",
  "password": "secure_password",
  "name": "Иван Иванов",
  "username": "ivan_ivanov" // опционально
}

Response: 201
{
  "user": {
    "id": 123,
    "email": "user@example.com",
    "name": "Иван Иванов",
    "username": "ivan_ivanov",
    "avatar_url": null,
    "created_at": "2025-01-01T12:00:00Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "..."
}
```

**POST /auth/login**
```json
Request:
{
  "email": "user@example.com",
  "password": "secure_password"
}

Response: 200
{
  "token": "...",
  "refresh_token": "...",
  "user": { ... }
}
```

**GET /auth/me**
```json
Response: 200
{
  "id": 123,
  "email": "user@example.com",
  "name": "Иван Иванов",
  "username": "ivan_ivanov",
  "avatar_url": "https://cdn.haneat.com/avatars/123.jpg",
  "bio": "Люблю готовить",
  "is_private": false,
  "stats": {
    "posts_count": 45,
    "reels_count": 12,
    "followers_count": 234,
    "following_count": 89
  },
  "subscription": {
    "type": "free", // free | plus
    "expires_at": null
  }
}
```

**POST /auth/refresh**
```json
Request:
{
  "refresh_token": "..."
}

Response: 200
{
  "token": "...",
  "refresh_token": "..."
}
```

### 3.3 Пользователи / Профиль

**GET /users/{user_id}**
```json
Response: 200
{
  "id": 123,
  "name": "Иван Иванов",
  "username": "ivan_ivanov",
  "avatar_url": "...",
  "bio": "Шеф-повар",
  "is_private": false,
  "is_following": false, // для текущего пользователя
  "is_followed_by": false,
  "stats": {
    "posts_count": 45,
    "reels_count": 12,
    "saved_count": 23,
    "followers_count": 234,
    "following_count": 89
  },
  "created_at": "2024-01-01T12:00:00Z"
}
```

**GET /users/{user_id}/posts**
```
Query params:
- cursor: string (опционально, для пагинации)
- limit: int (default: 20, max: 50)
- type: "all" | "recipe" | "photo" | "reel" | "text"

Response: 200
{
  "items": [
    {
      "id": 456,
      "type": "recipe",
      "title": "Боул с киноа",
      "thumbnail_url": "...",
      "created_at": "2025-01-01T12:00:00Z",
      "metrics": {
        "likes": 120,
        "comments": 4,
        "views": 1000
      }
    }
  ],
  "next_cursor": "eyJpZCI6NDU2fQ==",
  "has_more": true
}
```

**GET /users/{user_id}/reels**
```
Аналогично /posts, но фильтр type=reel
```

**GET /users/{user_id}/saved**
```
Список сохраненных постов пользователя
```

**POST /users/{user_id}/follow**
```json
Response: 200
{
  "following": true,
  "followers_count": 235
}
```

**DELETE /users/{user_id}/follow**
```json
Response: 200
{
  "following": false,
  "followers_count": 234
}
```

**GET /users/{user_id}/followers**
```
Query: cursor, limit

Response: 200
{
  "items": [
    {
      "id": 789,
      "name": "Мария Петрова",
      "username": "maria_p",
      "avatar_url": "...",
      "is_following": false
    }
  ],
  "next_cursor": "...",
  "has_more": true
}
```

**GET /users/{user_id}/following**
```
Аналогично /followers
```

**PATCH /users/me**
```json
Request:
{
  "name": "Новое имя",
  "bio": "Новая биография",
  "is_private": false,
  "avatar_url": "..." // после загрузки
}

Response: 200
{
  "user": { ... }
}
```

### 3.4 Публикации

**POST /posts**
```json
Request (Recipe):
{
  "type": "recipe",
  "title": "Боул с киноа",
  "description": "Легкий и питательный обед",
  "ingredients": [
    "1 стакан киноа",
    "200г нут (консервированный)",
    "100г шпинат",
    "1 авокадо",
    "2 ст.л. тахини"
  ],
  "steps": [
    {
      "number": 1,
      "text": "Промыть киноа и отварить согласно инструкции",
      "image_url": null
    },
    {
      "number": 2,
      "text": "Разогреть нут на сковороде с специями",
      "image_url": "https://cdn.haneat.com/posts/123/step2.jpg"
    }
  ],
  "prep_time_min": 25,
  "cook_time_min": 15,
  "servings": 2,
  "calories": 420,
  "tags": ["боул", "здоровье", "vegan"],
  "media": [
    {
      "type": "image",
      "url": "https://cdn.haneat.com/posts/123/main.jpg",
      "upload_id": "upload_abc123" // из /uploads/complete
    }
  ],
  "publish_to": ["feed", "community:5"], // feed, community:{id}
  "visibility": "public" // public | followers | private
}

Response: 201
{
  "id": 123,
  "type": "recipe",
  "status": "pending", // pending | published | rejected
  "created_at": "2025-01-01T12:00:00Z",
  "message": "Пост отправлен на модерацию"
}
```

**POST /posts (Photo)**
```json
Request:
{
  "type": "photo",
  "description": "Вкусный обед!",
  "media": [
    {
      "type": "image",
      "url": "...",
      "upload_id": "..."
    }
  ],
  "tags": ["обед", "фото"],
  "location": {
    "name": "Москва",
    "lat": 55.7558,
    "lng": 37.6173
  },
  "publish_to": ["feed"],
  "visibility": "public"
}
```

**POST /posts (Reel)**
```json
Request:
{
  "type": "reel",
  "description": "Как приготовить идеальный боул",
  "media": [
    {
      "type": "video",
      "url": "...",
      "upload_id": "...",
      "thumbnail_url": "..."
    }
  ],
  "tags": ["рецепт", "видео"],
  "duration_sec": 45,
  "publish_to": ["feed", "reels_feed"],
  "visibility": "public"
}
```

**GET /posts/{post_id}**
```json
Response: 200
{
  "id": 123,
  "type": "recipe",
  "user": {
    "id": 10,
    "name": "Иван Иванов",
    "username": "ivan_ivanov",
    "avatar_url": "..."
  },
  "title": "Боул с киноа",
  "description": "Легкий и питательный",
  "ingredients": [...],
  "steps": [...],
  "prep_time_min": 25,
  "servings": 2,
  "calories": 420,
  "tags": ["боул", "здоровье"],
  "media": [...],
  "metrics": {
    "likes": 120,
    "comments": 4,
    "saves": 23,
    "views": 1000,
    "shares": 5
  },
  "is_liked": false,
  "is_saved": false,
  "is_following_author": false,
  "community": null,
  "created_at": "2025-01-01T12:00:00Z",
  "updated_at": "2025-01-01T12:00:00Z"
}
```

**GET /feed**
```
Query params:
- cursor: string
- limit: int (default: 20)
- type: "all" | "reels" | "recipes" | "photos"

Response: 200
{
  "items": [
    {
      "id": 123,
      "type": "recipe",
      "user": { ... },
      "title": "Боул с киноа",
      "excerpt": "Легкий и питательный...",
      "thumbnail_url": "...",
      "media": [...],
      "metrics": {
        "likes": 120,
        "comments": 4,
        "views": 1000
      },
      "is_liked": false,
      "is_saved": false,
      "created_at": "2025-01-01T12:00:00Z",
      "community": {
        "id": 5,
        "name": "ЗОЖ",
        "avatar_url": "..."
      }
    }
  ],
  "next_cursor": "...",
  "has_more": true
}
```

**POST /posts/{post_id}/like**
```json
Response: 200
{
  "liked": true,
  "likes_count": 121
}
```

**DELETE /posts/{post_id}/like**
```json
Response: 200
{
  "liked": false,
  "likes_count": 120
}
```

**POST /posts/{post_id}/comment**
```json
Request:
{
  "text": "Отличный рецепт!",
  "parent_comment_id": null // для ответов
}

Response: 201
{
  "id": 456,
  "user": { ... },
  "text": "Отличный рецепт!",
  "created_at": "2025-01-01T12:00:00Z",
  "replies_count": 0
}
```

**GET /posts/{post_id}/comments**
```
Query: cursor, limit

Response: 200
{
  "items": [
    {
      "id": 456,
      "user": { ... },
      "text": "...",
      "created_at": "...",
      "replies": [
        {
          "id": 457,
          "user": { ... },
          "text": "...",
          "parent_comment_id": 456
        }
      ]
    }
  ],
  "next_cursor": "...",
  "has_more": true
}
```

**POST /posts/{post_id}/share**
```json
Request:
{
  "comment": "Смотрите, какой рецепт!" // опционально
}

Response: 201
{
  "share_id": 789,
  "shared_at": "2025-01-01T12:00:00Z"
}
```

**POST /posts/{post_id}/save**
```json
Response: 200
{
  "saved": true
}
```

**DELETE /posts/{post_id}/save**
```json
Response: 200
{
  "saved": false
}
```

**POST /posts/{post_id}/report**
```json
Request:
{
  "reason": "spam", // spam | inappropriate | copyright | other
  "description": "Описание проблемы"
}

Response: 200
{
  "reported": true,
  "message": "Жалоба отправлена на рассмотрение"
}
```

**DELETE /posts/{post_id}**
```json
Response: 204
```

### 3.5 Сообщества

**POST /communities**
```json
Request:
{
  "name": "ЗОЖ Сообщество",
  "slug": "healthy_life", // уникальный
  "description": "Сообщество о здоровом образе жизни",
  "cover_url": "...",
  "is_public": true
}

Response: 201
{
  "id": 5,
  "name": "ЗОЖ Сообщество",
  "slug": "healthy_life",
  "description": "...",
  "cover_url": "...",
  "admin_user_id": 123,
  "members_count": 1,
  "posts_count": 0,
  "created_at": "2025-01-01T12:00:00Z"
}
```

**GET /communities/{community_id}**
```json
Response: 200
{
  "id": 5,
  "name": "ЗОЖ Сообщество",
  "slug": "healthy_life",
  "description": "...",
  "cover_url": "...",
  "avatar_url": "...",
  "admin_user": { ... },
  "is_member": false,
  "is_admin": false,
  "members_count": 234,
  "posts_count": 45,
  "created_at": "2025-01-01T12:00:00Z"
}
```

**GET /communities/{community_id}/posts**
```
Аналогично /users/{id}/posts
```

**POST /communities/{community_id}/posts**
```
Создание поста от имени сообщества (только админы)
Body аналогично POST /posts, но добавляется:
{
  "publish_as_community": true,
  "community_id": 5
}
```

**POST /communities/{community_id}/join**
```json
Response: 200
{
  "joined": true,
  "members_count": 235
}
```

**DELETE /communities/{community_id}/join**
```json
Response: 200
{
  "joined": false,
  "members_count": 234
}
```

**GET /communities/{community_id}/members**
```
Query: cursor, limit, role (all | admin | moderator | member)

Response: 200
{
  "items": [
    {
      "id": 123,
      "name": "Иван Иванов",
      "username": "ivan_ivanov",
      "avatar_url": "...",
      "role": "admin", // admin | moderator | member
      "joined_at": "2025-01-01T12:00:00Z"
    }
  ],
  "next_cursor": "...",
  "has_more": true
}
```

### 3.6 Загрузка медиа

**POST /uploads/init**
```json
Request:
{
  "type": "image", // image | video
  "filename": "photo.jpg",
  "size_bytes": 2048000,
  "content_type": "image/jpeg"
}

Response: 200
{
  "upload_id": "upload_abc123",
  "presigned_url": "https://s3.amazonaws.com/bucket/...",
  "upload_url": "https://cdn.haneat.com/uploads/abc123",
  "expires_at": "2025-01-01T13:00:00Z"
}
```

**PUT {presigned_url}**
```
Загрузка файла напрямую в S3
Content-Type: image/jpeg
Body: binary file data
```

**POST /uploads/complete**
```json
Request:
{
  "upload_id": "upload_abc123",
  "type": "image"
}

Response: 200
{
  "url": "https://cdn.haneat.com/uploads/abc123.jpg",
  "thumbnail_url": "https://cdn.haneat.com/uploads/abc123_thumb.jpg",
  "processing": false // для видео будет true, затем webhook
}
```

**Для видео:**
После загрузки видео отправляется в очередь на обработку.
Когда обработка завершена, отправляется webhook или polling:

**GET /uploads/{upload_id}/status**
```json
Response: 200
{
  "status": "processing", // processing | completed | failed
  "progress": 45, // 0-100
  "url": null, // будет доступен после completed
  "hls_url": null,
  "thumbnail_url": null
}
```

### 3.7 Модерация (Admin)

**GET /moderation/pending**
```
Query: cursor, limit, type (all | post | comment | user)

Response: 200
{
  "items": [
    {
      "id": 123,
      "type": "post",
      "post_id": 456,
      "user": { ... },
      "reason": "auto_flagged", // auto_flagged | reported
      "flagged_by": null, // user_id если reported
      "created_at": "2025-01-01T12:00:00Z"
    }
  ],
  "next_cursor": "...",
  "has_more": true
}
```

**POST /moderation/{item_id}/approve**
```json
Request:
{
  "comment": "Контент соответствует правилам" // опционально
}

Response: 200
{
  "approved": true,
  "post_id": 456,
  "status": "published"
}
```

**POST /moderation/{item_id}/reject**
```json
Request:
{
  "reason": "spam", // spam | inappropriate | copyright | other
  "comment": "Нарушение правил сообщества"
}

Response: 200
{
  "rejected": true,
  "post_id": 456,
  "status": "rejected"
}
```

### 3.8 Аналитика (для авторов с Plus)

**GET /analytics/posts/{post_id}**
```json
Response: 200
{
  "post_id": 123,
  "views": {
    "total": 1000,
    "unique": 850,
    "by_day": [
      {"date": "2025-01-01", "count": 100},
      {"date": "2025-01-02", "count": 150}
    ]
  },
  "engagement": {
    "likes": 120,
    "comments": 4,
    "saves": 23,
    "shares": 5,
    "ctr": 0.12 // click-through rate
  },
  "demographics": {
    "age_groups": {...},
    "locations": {...}
  }
}
```

**GET /analytics/profile**
```
Общая аналитика профиля автора
```

---

## 4. Схема БД

### 4.1 PostgreSQL Schema

```sql
-- Пользователи
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    username VARCHAR(100) UNIQUE,
    avatar_url TEXT,
    bio TEXT,
    is_private BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    subscription_type VARCHAR(20) DEFAULT 'free', -- free | plus
    subscription_expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username) WHERE username IS NOT NULL;

-- Публикации
CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    community_id INTEGER REFERENCES communities(id) ON DELETE SET NULL,
    type VARCHAR(20) NOT NULL, -- photo | recipe | reel | text
    title VARCHAR(500),
    description TEXT,
    body JSONB, -- для рецептов: ingredients, steps и т.д.
    status VARCHAR(20) DEFAULT 'pending', -- pending | published | rejected | deleted
    visibility VARCHAR(20) DEFAULT 'public', -- public | followers | private
    publish_to TEXT[], -- массив: ['feed', 'community:5']
    tags TEXT[],
    location_name VARCHAR(255),
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_community_id ON posts(community_id) WHERE community_id IS NOT NULL;
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_type ON posts(type);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_posts_tags ON posts USING GIN(tags);
CREATE INDEX idx_posts_published_at ON posts(published_at DESC) WHERE status = 'published';

-- Медиа файлы
CREATE TABLE post_media (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- image | video
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    hls_url TEXT, -- для видео
    width INTEGER,
    height INTEGER,
    duration_sec INTEGER, -- для видео
    file_size_bytes BIGINT,
    position INTEGER DEFAULT 0, -- порядок в галерее
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_post_media_post_id ON post_media(post_id);

-- Рецепты (расширенная информация)
CREATE TABLE recipes (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL UNIQUE REFERENCES posts(id) ON DELETE CASCADE,
    prep_time_min INTEGER,
    cook_time_min INTEGER,
    servings INTEGER,
    calories INTEGER,
    nutrition_json JSONB, -- полная информация о питании
    source_language VARCHAR(10), -- если импортирован
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_recipes_post_id ON recipes(post_id);

-- Ингредиенты рецепта
CREATE TABLE recipe_ingredients (
    id SERIAL PRIMARY KEY,
    recipe_post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    text VARCHAR(500) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(recipe_post_id, position)
);

CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_post_id);

-- Шаги рецепта
CREATE TABLE recipe_steps (
    id SERIAL PRIMARY KEY,
    recipe_post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    number INTEGER NOT NULL,
    text TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(recipe_post_id, number)
);

CREATE INDEX idx_recipe_steps_recipe ON recipe_steps(recipe_post_id);

-- Сообщества
CREATE TABLE communities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    cover_url TEXT,
    avatar_url TEXT,
    admin_user_id INTEGER NOT NULL REFERENCES users(id),
    is_public BOOLEAN DEFAULT TRUE,
    members_count INTEGER DEFAULT 0,
    posts_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_communities_slug ON communities(slug);
CREATE INDEX idx_communities_admin ON communities(admin_user_id);

-- Участники сообществ
CREATE TABLE community_members (
    id SERIAL PRIMARY KEY,
    community_id INTEGER NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member', -- admin | moderator | member
    joined_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(community_id, user_id)
);

CREATE INDEX idx_community_members_community ON community_members(community_id);
CREATE INDEX idx_community_members_user ON community_members(user_id);

-- Лайки
CREATE TABLE likes (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

CREATE INDEX idx_likes_user ON likes(user_id);
CREATE INDEX idx_likes_post ON likes(post_id);
CREATE INDEX idx_likes_created_at ON likes(created_at DESC);

-- Комментарии
CREATE TABLE comments (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_comment_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'published', -- published | deleted | hidden
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

CREATE INDEX idx_comments_post ON comments(post_id);
CREATE INDEX idx_comments_user ON comments(user_id);
CREATE INDEX idx_comments_parent ON comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

-- Подписки
CREATE TABLE followers (
    id SERIAL PRIMARY KEY,
    follower_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(follower_id, followee_id),
    CHECK (follower_id != followee_id)
);

CREATE INDEX idx_followers_follower ON followers(follower_id);
CREATE INDEX idx_followers_followee ON followers(followee_id);

-- Сохраненные посты
CREATE TABLE saved_posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

CREATE INDEX idx_saved_posts_user ON saved_posts(user_id);
CREATE INDEX idx_saved_posts_post ON saved_posts(post_id);

-- Репосты
CREATE TABLE reposts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    comment TEXT, -- комментарий к репосту
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

CREATE INDEX idx_reposts_user ON reposts(user_id);
CREATE INDEX idx_reposts_post ON reposts(post_id);

-- Очередь модерации
CREATE TABLE moderation_queue (
    id SERIAL PRIMARY KEY,
    post_id INTEGER REFERENCES posts(id) ON DELETE CASCADE,
    comment_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- post | comment | user
    reason VARCHAR(50) NOT NULL, -- auto_flagged | reported | manual
    reported_by_user_id INTEGER REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'pending', -- pending | approved | rejected
    assigned_moderator_id INTEGER REFERENCES users(id),
    moderator_comment TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    reviewed_at TIMESTAMP
);

CREATE INDEX idx_moderation_queue_status ON moderation_queue(status);
CREATE INDEX idx_moderation_queue_type ON moderation_queue(type);
CREATE INDEX idx_moderation_queue_created_at ON moderation_queue(created_at DESC);

-- События аналитики
CREATE TABLE analytics_events (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    post_id INTEGER REFERENCES posts(id),
    event_type VARCHAR(50) NOT NULL, -- view_post, like, save, follow, etc.
    metadata JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_analytics_events_user ON analytics_events(user_id);
CREATE INDEX idx_analytics_events_post ON analytics_events(post_id);
CREATE INDEX idx_analytics_events_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_events_created_at ON analytics_events(created_at DESC);

-- Триггеры для обновления счетчиков
CREATE OR REPLACE FUNCTION update_posts_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET posts_count = posts_count + 1 WHERE id = NEW.user_id;
        IF NEW.community_id IS NOT NULL THEN
            UPDATE communities SET posts_count = posts_count + 1 WHERE id = NEW.community_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET posts_count = posts_count - 1 WHERE id = OLD.user_id;
        IF OLD.community_id IS NOT NULL THEN
            UPDATE communities SET posts_count = posts_count - 1 WHERE id = OLD.community_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_posts_count
AFTER INSERT OR DELETE ON posts
FOR EACH ROW EXECUTE FUNCTION update_posts_count();

-- Аналогично для followers, likes и т.д.
```

### 4.2 Redis Структуры

```python
# Кэш ленты пользователя
feed:{user_id} = Sorted Set
  - score: timestamp (для сортировки)
  - member: post_id

# Счетчики (для быстрого доступа)
post:{post_id}:likes = Integer
post:{post_id}:comments = Integer
post:{post_id}:views = Integer
post:{post_id}:saves = Integer

# Кэш метрик поста
post:{post_id}:metrics = Hash
  - likes: 120
  - comments: 4
  - views: 1000
  - saves: 23

# Rate limiting
rate_limit:{user_id}:{action} = Integer (TTL: 60s)

# Сессии
session:{token} = JSON (user data, expires_at)

# Очередь задач
queue:transcoding = List
queue:notifications = List
```

---

## 5. UI/UX Структура

### 5.1 Навигация (Bottom Navigation)

```
┌─────────────────────────────────────┐
│  [Home] [Search] [Create] [Feed] [Profile] │
└─────────────────────────────────────┘
```

### 5.2 Экраны

#### 5.2.1 Profile Screen

```
┌─────────────────────────────────────┐
│  [←]                    [⚙️] [⋯]     │
├─────────────────────────────────────┤
│                                     │
│    [Cover Image - опционально]      │
│                                     │
│         [Avatar]                    │
│      Иван Иванов                    │
│      @ivan_ivanov                   │
│      Шеф-повар, люблю готовить      │
│                                     │
│  [Follow] [Message] [Edit Profile]  │
│                                     │
│  45 Posts | 12 Reels | 23 Saved    │
│  234 Followers | 89 Following       │
│                                     │
│  ┌─────┬─────┬─────┐                │
│  │Posts│Reels│Saved│                │
│  └─────┴─────┴─────┘                │
│                                     │
│  ┌───┬───┬───┐                      │
│  │[ ]│[ ]│[ ]│  Posts Grid (3 cols) │
│  ├───┼───┼───┤                      │
│  │[ ]│[ ]│[ ]│                      │
│  └───┴───┴───┘                      │
└─────────────────────────────────────┘
```

**Компоненты:**
- `ProfileHeader` - аватар, имя, bio, кнопки действий
- `ProfileStats` - счетчики постов, подписчиков
- `ProfileTabs` - переключение между Posts/Reels/Saved
- `PostsGrid` - сетка миниатюр постов
- `ReelsList` - вертикальный список рилсов
- `SavedList` - список сохраненных

#### 5.2.2 Home Feed Screen

```
┌─────────────────────────────────────┐
│  H.A.N. Eat          [🔍] [✉️]      │
├─────────────────────────────────────┤
│  [Stories Strip - опционально]      │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [Avatar] Иван Иванов    [⋯] │   │
│  │ 2 часа назад                 │   │
│  ├─────────────────────────────┤   │
│  │                             │   │
│  │    [Post Image/Recipe]      │   │
│  │                             │   │
│  ├─────────────────────────────┤   │
│  │ ❤️ 120  💬 4  🔖 23  📤 5  │   │
│  │ Боул с киноа...             │   │
│  │ #боул #здоровье             │   │
│  │ [View all 4 comments]       │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Next Post...]                     │
└─────────────────────────────────────┘
```

**Компоненты:**
- `FeedItem` - карточка поста
- `PostHeader` - автор, время, меню
- `PostMedia` - изображение/видео/рецепт
- `PostActions` - лайк, комментарий, сохранить, поделиться
- `PostMetrics` - счетчики лайков, комментариев
- `InfiniteScroll` - lazy loading

#### 5.2.3 Create Post Screen

```
┌─────────────────────────────────────┐
│  [←] Создать пост            [Next] │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Выберите тип:               │   │
│  │                             │   │
│  │  [📷 Photo]  [📝 Recipe]   │   │
│  │  [🎥 Reel]   [📄 Text]     │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Если Recipe:]                     │
│  ┌─────────────────────────────┐   │
│  │ Title: [Боул с киноа]       │   │
│  │ Description: [...]          │   │
│  │                             │   │
│  │ Ingredients:                │   │
│  │  [+ Add ingredient]        │   │
│  │                             │   │
│  │ Steps:                      │   │
│  │  [+ Add step]              │   │
│  │                             │   │
│  │ Prep time: [25] min         │   │
│  │ Servings: [2]               │   │
│  └─────────────────────────────┘   │
│                                     │
│  Publish to:                        │
│  ☑ Feed                             │
│  ☐ Community: [Select...]          │
│                                     │
│  Visibility: [Public ▼]            │
│                                     │
│  [Publish]                          │
└─────────────────────────────────────┘
```

**Компоненты:**
- `PostTypeSelector` - выбор типа поста
- `PhotoUploader` - загрузка фото
- `RecipeForm` - форма создания рецепта
- `ReelUploader` - загрузка видео
- `PublishOptions` - настройки публикации

#### 5.2.4 Community Page

```
┌─────────────────────────────────────┐
│  [←]                    [⚙️] [⋯]     │
├─────────────────────────────────────┤
│                                     │
│    [Cover Image]                    │
│                                     │
│    [Avatar]                         │
│    ЗОЖ Сообщество                   │
│    @healthy_life                    │
│    Сообщество о здоровом образе...  │
│                                     │
│  [Join] [Message]                   │
│                                     │
│  234 Members | 45 Posts             │
│                                     │
│  ┌─────┬─────┬─────┐                │
│  │Feed │About│Members│               │
│  └─────┴─────┴─────┘                │
│                                     │
│  [Community Posts Feed...]          │
└─────────────────────────────────────┘
```

#### 5.2.5 Recipe Detail Screen

```
┌─────────────────────────────────────┐
│  [←]                    [❤️] [⋯]     │
├─────────────────────────────────────┤
│                                     │
│    [Hero Image - можно свайпнуть]   │
│                                     │
│  Боул с киноа                       │
│  Иван Иванов                        │
│                                     │
│  ⏱ 25 мин  🍽 2 порции  🔥 420 ккал│
│                                     │
│  [Save] [Add to Plan] [Share]       │
│                                     │
│  Ингредиенты:                       │
│  ☐ 1 стакан киноа                   │
│  ☐ 200г нут                         │
│  ☐ 100г шпинат                      │
│                                     │
│  Шаги:                              │
│  1. Промыть киноа...                │
│     [Step image]                    │
│  2. Разогреть нут...                │
│                                     │
│  Комментарии (4):                   │
│  [View all comments]                │
└─────────────────────────────────────┘
```

---

## 6. Алгоритмы и Логика

### 6.1 Feed Ranking Algorithm

**Формула ранжирования:**
```
score = w1 * user_similarity 
      + w2 * recency 
      + w3 * engagement 
      + w4 * author_score 
      + w5 * business_boost
```

**Компоненты:**

1. **user_similarity** (0-1)
   - История лайков пользователя
   - Подписки
   - Сохраненные посты
   - Теги интересов

2. **recency** (0-1)
   - Время с момента публикации
   - Экспоненциальное затухание

3. **engagement** (0-1)
   - Like rate = likes / views
   - Comments rate
   - Shares rate
   - Время последних взаимодействий

4. **author_score** (0-1)
   - Историческая вовлеченность автора
   - Количество подписчиков
   - Качество контента (метрики)

5. **business_boost** (0-2)
   - Промо-посты (×1.5)
   - Посты сообщества для участников (×1.2)
   - Plus подписка автора (×1.1)

**Реализация (Phase 0 - Rule-based):**

```python
def calculate_feed_score(post, user, now):
    # 1. User similarity
    similarity = calculate_user_similarity(post, user)
    
    # 2. Recency (exponential decay)
    hours_ago = (now - post.created_at).total_seconds() / 3600
    recency = math.exp(-hours_ago / 24)  # half-life 24 hours
    
    # 3. Engagement
    engagement = (
        post.like_rate * 0.4 +
        post.comment_rate * 0.3 +
        post.share_rate * 0.3
    )
    
    # 4. Author score
    author_score = min(post.author.avg_engagement, 1.0)
    
    # 5. Business boost
    boost = 1.0
    if post.is_promoted:
        boost *= 1.5
    if post.community_id and user.is_member(post.community_id):
        boost *= 1.2
    if post.author.subscription_type == 'plus':
        boost *= 1.1
    
    # Final score
    score = (
        0.3 * similarity +
        0.2 * recency +
        0.3 * engagement +
        0.15 * author_score
    ) * boost
    
    return score
```

### 6.2 Распространение контента

**При публикации поста:**

1. **Обычный пост пользователя:**
   - Добавляется в профиль автора
   - Отправляется в ленты всех подписчиков (fanout-on-write для < 1000 подписчиков)
   - Для больших авторов: fanout-on-read с кэшированием
   - Может попасть в рекомендованную ленту (если score высокий)

2. **Пост от сообщества:**
   - Публикуется в сообществе
   - Дублируется в общую ленту
   - Отправляется в ленты подписчиков сообщества

3. **Reel:**
   - Публикуется в Reels feed
   - Появляется в общей ленте
   - Приоритет в рекомендациях

4. **Репост:**
   - Создается ссылка на оригинал
   - Отображается в профиле репостнувшего
   - Попадает в ленту подписчиков репостнувшего

**Реализация:**

```python
async def publish_post(post):
    # 1. Сохранить пост
    await db.posts.insert(post)
    
    # 2. Если публикация в feed
    if 'feed' in post.publish_to:
        # Fanout to followers
        followers = await get_followers(post.user_id)
        
        if len(followers) < 1000:
            # Fanout-on-write
            for follower_id in followers:
                await redis.zadd(
                    f'feed:{follower_id}',
                    {post.id: post.created_at.timestamp()}
                )
        else:
            # Fanout-on-read (cache author's recent posts)
            await cache_author_recent_posts(post.user_id, post.id)
    
    # 3. Если публикация в сообщество
    if post.community_id:
        await publish_to_community(post)
        # Также в feed подписчиков сообщества
        community_followers = await get_community_followers(post.community_id)
        for follower_id in community_followers:
            await redis.zadd(
                f'feed:{follower_id}',
                {post.id: post.created_at.timestamp()}
            )
    
    # 4. Если Reel
    if post.type == 'reel':
        await redis.zadd('reels_feed', {post.id: post.created_at.timestamp()})
    
    # 5. Отправить на модерацию
    if should_moderate(post):
        await send_to_moderation(post)
    else:
        post.status = 'published'
        await db.posts.update(post)
```

---

## 7. Модерация

### 7.1 Автоматическая модерация

**Проверки:**

1. **NSFW Detection**
   - OpenAI Moderation API
   - Custom ML model для изображений

2. **Текстовая проверка**
   - Запрещенные слова
   - Спам-паттерны
   - Токсичность

3. **Медиа проверка**
   - Размер файла
   - Формат
   - Вирус-сканирование

4. **Правила для рецептов**
   - Аллергены должны быть указаны
   - Валидация ингредиентов

**Реализация:**

```python
async def auto_moderate(post):
    checks = []
    
    # 1. Текст
    if post.description:
        text_check = await check_text(post.description)
        checks.append(text_check)
    
    # 2. Изображения
    for media in post.media:
        if media.type == 'image':
            image_check = await check_image(media.url)
            checks.append(image_check)
    
    # 3. Видео
    for media in post.media:
        if media.type == 'video':
            video_check = await check_video(media.url)
            checks.append(video_check)
    
    # 4. Рецепт-специфичные проверки
    if post.type == 'recipe':
        recipe_check = await check_recipe(post)
        checks.append(recipe_check)
    
    # Решение
    if any(c.flagged for c in checks):
        post.status = 'pending'
        await send_to_moderation_queue(post, reason='auto_flagged')
    else:
        post.status = 'published'
    
    return post
```

### 7.2 Ручная модерация

**Админ-панель:**
- Список постов на модерации
- Просмотр контента
- Approve/Reject с комментарием
- Блокировка пользователей

**Приоритеты:**
1. Жалобы пользователей
2. Авто-флаги
3. Новые пользователи (первые 5 постов)

---

## 8. Медиа Обработка

### 8.1 Загрузка

1. Клиент запрашивает presigned URL
2. Загружает файл напрямую в S3
3. Уведомляет backend о завершении
4. Backend ставит задачу на обработку

### 8.2 Обработка изображений

- Resize до нескольких размеров (thumbnail, medium, large)
- Оптимизация (WebP, JPEG quality)
- Генерация превью

### 8.3 Обработка видео

1. **Транс-кодинг:**
   - HLS (для стриминга)
   - MP4 720p
   - MP4 480p (для медленных соединений)
   - Thumbnail (frame at 1s)

2. **Workers:**
   - FFmpeg workers в отдельном пуле
   - Очередь задач (RabbitMQ/Redis)
   - Прогресс обработки

3. **CDN:**
   - Cloudflare/CloudFront
   - Кэширование
   - Географическое распределение

---

## 9. Масштабирование

### 9.1 Database

- **Read Replicas** для чтения
- **Sharding** по user_id (если нужно)
- **Connection Pooling**
- **Query Optimization**

### 9.2 Caching

- **Redis** для лент (TTL: 5-15 минут)
- **CDN** для медиа
- **Application-level cache** для частых запросов

### 9.3 Feed Generation

**Fanout Strategy:**

- **Small authors (< 1000 followers):** Fanout-on-write
- **Large authors (> 1000 followers):** Fanout-on-read
- **Hybrid:** Кэширование последних постов автора

### 9.4 Rate Limiting

- По пользователю: 10 постов/час
- По IP: 100 запросов/минуту
- Загрузка медиа: 5 файлов/минуту

### 9.5 Monitoring

- **Metrics:** Prometheus
- **Logs:** ELK Stack или CloudWatch
- **Errors:** Sentry
- **Uptime:** Pingdom/UptimeRobot

---

## 10. Списки задач

### 10.1 Phase 1: Базовая инфраструктура

#### Backend
- [ ] Настроить проект (FastAPI/NestJS)
- [ ] Настроить PostgreSQL + миграции
- [ ] Настроить Redis
- [ ] Настроить S3/Object Storage
- [ ] Реализовать Auth (JWT, refresh tokens)
- [ ] Базовые CRUD для users
- [ ] Базовые CRUD для posts
- [ ] API для загрузки медиа

**Acceptance:**
- Можно зарегистрироваться и войти
- Можно создать пост с текстом
- Можно загрузить изображение

#### Frontend
- [ ] Настроить Flutter проект
- [ ] Реализовать Auth экраны (Login/Register)
- [ ] Реализовать базовую навигацию
- [ ] Реализовать Profile Screen (базовая версия)
- [ ] Реализовать Create Post Screen (только текст)

**Acceptance:**
- Можно зарегистрироваться в приложении
- Можно войти
- Виден профиль пользователя
- Можно создать текстовый пост

### 10.2 Phase 2: Публикации и лента

#### Backend
- [ ] Реализовать типы постов (photo, recipe, reel)
- [ ] Реализовать лайки
- [ ] Реализовать комментарии
- [ ] Реализовать сохранение постов
- [ ] Реализовать базовую ленту (по подпискам)
- [ ] Реализовать подписки (follow/unfollow)

**Acceptance:**
- Можно создать пост с фото
- Можно создать рецепт
- Можно лайкнуть пост
- Можно прокомментировать
- Видна лента постов от подписок

#### Frontend
- [ ] Реализовать Home Feed Screen
- [ ] Реализовать Post Detail Screen
- [ ] Реализовать Create Recipe Screen
- [ ] Реализовать Create Photo Post Screen
- [ ] Реализовать лайки/комментарии UI

**Acceptance:**
- Видна лента постов
- Можно открыть пост и увидеть детали
- Можно создать рецепт с шагами
- Можно лайкнуть и прокомментировать

### 10.3 Phase 3: Сообщества

#### Backend
- [ ] Реализовать CRUD для communities
- [ ] Реализовать участников сообществ
- [ ] Реализовать публикацию от сообщества
- [ ] Обновить feed для включения постов сообществ

**Acceptance:**
- Можно создать сообщество
- Можно присоединиться к сообществу
- Админ может публиковать от имени сообщества
- Посты сообщества видны в ленте

#### Frontend
- [ ] Реализовать Community Page
- [ ] Реализовать Create Community Screen
- [ ] Обновить Create Post для выбора сообщества

**Acceptance:**
- Можно просмотреть страницу сообщества
- Можно создать сообщество
- При создании поста можно выбрать сообщество

### 10.4 Phase 4: Рилсы и видео

#### Backend
- [ ] Реализовать загрузку видео
- [ ] Настроить очередь транс-кодинга
- [ ] Реализовать FFmpeg workers
- [ ] Реализовать Reels feed
- [ ] Реализовать метрики просмотров

**Acceptance:**
- Можно загрузить видео
- Видео обрабатывается и доступно для просмотра
- Рилсы появляются в Reels feed

#### Frontend
- [ ] Реализовать Reel Upload Screen
- [ ] Реализовать Reels Feed (вертикальная прокрутка)
- [ ] Реализовать Video Player
- [ ] Реализовать метрики на карточке рилса

**Acceptance:**
- Можно загрузить рилс
- Можно просмотреть рилсы в вертикальной ленте
- Видео воспроизводится корректно

### 10.5 Phase 5: Модерация

#### Backend
- [ ] Интегрировать OpenAI Moderation API
- [ ] Реализовать авто-модерацию
- [ ] Реализовать очередь модерации
- [ ] Реализовать Admin API
- [ ] Реализовать систему жалоб

**Acceptance:**
- Посты автоматически проверяются
- Подозрительные посты идут в pending
- Админ может одобрить/отклонить пост
- Пользователи могут пожаловаться на пост

#### Frontend
- [ ] Реализовать Admin Panel (web или в приложении)
- [ ] Реализовать Report Post UI

**Acceptance:**
- Админ видит очередь модерации
- Админ может одобрить/отклонить
- Пользователь может пожаловаться

### 10.6 Phase 6: Алгоритм ранжирования

#### Backend
- [ ] Реализовать rule-based ranking
- [ ] Реализовать сбор метрик для ML
- [ ] Реализовать A/B тестирование
- [ ] Оптимизировать feed generation

**Acceptance:**
- Лента ранжируется по релевантности
- Новые посты появляются выше
- Популярные посты получают буст

### 10.7 Phase 7: H.A.N. Plus

#### Backend
- [ ] Реализовать подписки (Stripe/PayPal)
- [ ] Реализовать аналитику для авторов
- [ ] Реализовать приоритет в ленте для Plus
- [ ] Реализовать offline кэш для Saved

**Acceptance:**
- Можно купить Plus подписку
- Авторы видят аналитику своих постов
- Plus пользователи видят меньше рекламы

#### Frontend
- [ ] Реализовать Subscription Screen
- [ ] Реализовать Analytics Screen для авторов
- [ ] Реализовать offline режим для Saved

**Acceptance:**
- Можно купить подписку в приложении
- Авторы видят метрики
- Сохраненные рецепты доступны оффлайн

---

## 11. Критерии приёмки (общие)

### Функциональность
- ✅ Все фичи работают согласно спецификации
- ✅ Нет критических багов
- ✅ Производительность приемлема (< 2s загрузка ленты)

### Безопасность
- ✅ Пароли хешируются (bcrypt/argon2)
- ✅ JWT токены валидны и имеют expiration
- ✅ Rate limiting работает
- ✅ Медиа файлы проверяются на размер/тип

### UX
- ✅ Плавная анимация (60 FPS)
- ✅ Обработка ошибок с понятными сообщениями
- ✅ Offline режим для базовых функций
- ✅ Push уведомления работают

### Масштабируемость
- ✅ Система выдерживает 1000+ одновременных пользователей
- ✅ База данных оптимизирована (индексы)
- ✅ Кэширование работает эффективно

---

## 12. Дополнительные заметки

### Технический долг
- Регулярно обновлять зависимости
- Рефакторинг при росте кодовой базы
- Оптимизация запросов к БД

### Мониторинг
- Настроить алерты на критические метрики
- Отслеживать ошибки в реальном времени
- Анализировать производительность

### Документация
- Поддерживать актуальную API документацию
- Документировать архитектурные решения
- README для разработчиков

---

**Конец документа**

