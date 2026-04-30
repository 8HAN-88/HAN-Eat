# 📋 Полное ТЗ: Профили и Система Сообществ

## 🎯 Что мы строим

Гибридная социальная платформа (VK + Instagram) с фокусом на рецепты и короткие видео:
- ✅ Профили пользователей с контентом
- ✅ Система сообществ
- ✅ Персонализированная лента
- ✅ Модерация контента
- ✅ Монетизация (H.A.N. Plus)

## 📚 Документация

### Основные документы

1. **[FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md)** ⭐
   - Полное техническое задание
   - Архитектура системы
   - API спецификация
   - Схема БД
   - UI/UX структура
   - Алгоритмы ранжирования
   - Модерация
   - Масштабирование

2. **[IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md)**
   - Детальный чеклист задач
   - Критерии приёмки для каждой фичи
   - Разбивка по фазам разработки

3. **[QUICK_START.md](./QUICK_START.md)**
   - Быстрый старт для разработчиков
   - Настройка окружения
   - Первые шаги

4. **[FLUTTER_STRUCTURE.md](./FLUTTER_STRUCTURE.md)**
   - Структура Flutter приложения
   - Организация кода
   - Примеры компонентов

5. **[ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md)**
   - Обоснование архитектурных решений
   - Выбор технологий
   - Стратегии масштабирования

6. **[backend/api_spec.yaml](../backend/api_spec.yaml)**
   - OpenAPI спецификация
   - Все endpoints с примерами

## 🚀 Быстрый старт

### Для разработчиков

1. Прочитайте [QUICK_START.md](./QUICK_START.md)
2. Изучите [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md) (раздел 3 - API)
3. Следуйте [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md)

### Для менеджеров проекта

1. Изучите раздел "Списки задач" в [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md)
2. Используйте [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md) для планирования спринтов

## 📊 Основные фичи

### ✅ Реализовано (текущий проект)
- Базовые рецепты из Spoonacular
- Рецепты пользователей (community_posts)
- Видео в рецептах
- Комментарии к рецептам
- Подписки на авторов
- 50/50 смешивание рецептов в Menu

### 🚧 К реализации (новое ТЗ)
- Полноценные профили пользователей
- Система сообществ
- Лента с ранжированием
- Рилсы (короткие видео)
- Модерация контента
- H.A.N. Plus подписка

## 🏗️ Архитектура

```
Mobile App (Flutter)
    ↓
API Gateway (FastAPI/NestJS)
    ↓
Services (Auth, Posts, Feed, Media, Moderation)
    ↓
PostgreSQL + Redis + S3
```

## 📝 API Endpoints (основные)

### Auth
- `POST /auth/register` - Регистрация
- `POST /auth/login` - Вход
- `GET /auth/me` - Текущий пользователь

### Users
- `GET /users/{id}` - Профиль
- `GET /users/{id}/posts` - Посты пользователя
- `POST /users/{id}/follow` - Подписаться

### Posts
- `POST /posts` - Создать пост
- `GET /posts/{id}` - Детали поста
- `POST /posts/{id}/like` - Лайкнуть
- `POST /posts/{id}/comment` - Комментировать

### Feed
- `GET /feed` - Персональная лента
- `GET /feed?type=reels` - Лента рилсов

### Communities
- `POST /communities` - Создать сообщество
- `GET /communities/{id}` - Страница сообщества
- `POST /communities/{id}/join` - Присоединиться

Полный список: см. [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md) раздел 3

## 🗄️ База данных

Основные таблицы:
- `users` - Пользователи
- `posts` - Публикации
- `communities` - Сообщества
- `followers` - Подписки
- `likes` - Лайки
- `comments` - Комментарии
- `saved_posts` - Сохраненные

Полная схема: см. [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md) раздел 4

## 📱 UI Экраны

1. **Profile Screen** - Профиль с вкладками
2. **Home Feed** - Лента постов
3. **Create Post** - Создание публикации
4. **Community Page** - Страница сообщества
5. **Post Detail** - Детали поста/рецепта
6. **Reels Feed** - Вертикальная лента видео

Детали: см. [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md) раздел 5

## 🎯 План реализации

### Phase 1: Базовая инфраструктура
- Auth, Users, базовые Posts
- **Срок:** 2-3 недели

### Phase 2: Публикации и лента
- Типы постов, лайки, комментарии
- Базовая лента
- **Срок:** 3-4 недели

### Phase 3: Сообщества
- CRUD сообществ
- Публикация от сообщества
- **Срок:** 2-3 недели

### Phase 4: Рилсы и видео
- Загрузка видео
- Транс-кодинг
- Reels feed
- **Срок:** 3-4 недели

### Phase 5: Модерация
- Авто-модерация
- Админ-панель
- **Срок:** 2-3 недели

### Phase 6: Алгоритм ранжирования
- Rule-based ranking
- ML модель (опционально)
- **Срок:** 2-3 недели

### Phase 7: H.A.N. Plus
- Подписки
- Аналитика
- **Срок:** 2-3 недели

**Общий срок:** ~18-24 недели (4.5-6 месяцев)

## ✅ Критерии приёмки

### Функциональность
- Все фичи работают согласно спецификации
- Нет критических багов
- Производительность < 2s загрузка ленты

### Безопасность
- Пароли хешируются
- JWT токены валидны
- Rate limiting работает

### UX
- Плавная анимация (60 FPS)
- Обработка ошибок
- Offline режим для базовых функций

## 📞 Контакты и вопросы

При возникновении вопросов по ТЗ:
1. Проверьте соответствующий раздел в [FULL_SPEC_PROFILES_COMMUNITIES.md](./FULL_SPEC_PROFILES_COMMUNITIES.md)
2. Изучите [ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md)
3. Обратитесь к команде разработки

---

**Версия:** 1.0  
**Последнее обновление:** 2025-01-XX

