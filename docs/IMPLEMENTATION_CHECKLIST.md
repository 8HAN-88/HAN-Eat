# Чеклист реализации: Профили и Сообщества

## Быстрый старт

### Шаг 1: Настройка окружения
- [ ] Клонировать репозиторий
- [ ] Установить зависимости (Python/Node.js, Flutter)
- [ ] Настроить PostgreSQL
- [ ] Настроить Redis
- [ ] Настроить S3/Object Storage
- [ ] Создать .env файлы

### Шаг 2: База данных
- [ ] Применить миграции
- [ ] Создать тестовые данные (seed)
- [ ] Проверить индексы

### Шаг 3: Backend API
- [ ] Запустить сервер разработки
- [ ] Протестировать базовые endpoints
- [ ] Настроить CORS

### Шаг 4: Frontend
- [ ] Запустить Flutter приложение
- [ ] Подключить к API
- [ ] Протестировать базовые экраны

---

## Детальный чеклист по фичам

### ✅ Auth (Аутентификация)

#### Backend
- [ ] POST /auth/register
- [ ] POST /auth/login
- [ ] GET /auth/me
- [ ] POST /auth/refresh
- [ ] POST /auth/logout
- [ ] Валидация email/password
- [ ] Хеширование паролей (bcrypt)
- [ ] JWT токены (access + refresh)
- [ ] Middleware для проверки токенов

#### Frontend
- [ ] Login Screen
- [ ] Register Screen
- [ ] Сохранение токенов (secure storage)
- [ ] Автоматический refresh токенов
- [ ] Logout функционал

**Acceptance:**
- Можно зарегистрироваться
- Можно войти
- Токен сохраняется и используется для запросов
- При истечении токена происходит автоматический refresh

---

### ✅ Profile (Профиль)

#### Backend
- [ ] GET /users/{id}
- [ ] PATCH /users/me
- [ ] GET /users/{id}/posts
- [ ] GET /users/{id}/reels
- [ ] GET /users/{id}/saved
- [ ] GET /users/{id}/followers
- [ ] GET /users/{id}/following
- [ ] POST /users/{id}/follow
- [ ] DELETE /users/{id}/follow
- [ ] Обновление счетчиков (триггеры)

#### Frontend
- [ ] Profile Screen
- [ ] Profile Header (аватар, имя, bio)
- [ ] Profile Stats (посты, подписчики)
- [ ] Profile Tabs (Posts/Reels/Saved)
- [ ] Posts Grid (3 колонки)
- [ ] Reels List
- [ ] Saved List
- [ ] Edit Profile Screen
- [ ] Follow/Unfollow кнопка

**Acceptance:**
- Виден профиль пользователя
- Можно переключать вкладки
- Видны посты/рилсы/сохраненное
- Можно подписаться/отписаться
- Можно редактировать свой профиль

---

### ✅ Posts (Публикации)

#### Backend
- [ ] POST /posts (создание)
- [ ] GET /posts/{id}
- [ ] PATCH /posts/{id}
- [ ] DELETE /posts/{id}
- [ ] POST /posts/{id}/like
- [ ] DELETE /posts/{id}/like
- [ ] POST /posts/{id}/comment
- [ ] GET /posts/{id}/comments
- [ ] POST /posts/{id}/share
- [ ] POST /posts/{id}/save
- [ ] DELETE /posts/{id}/save
- [ ] POST /posts/{id}/report
- [ ] Валидация типов постов
- [ ] Обработка рецептов (ingredients, steps)

#### Frontend
- [ ] Create Post Screen
- [ ] Post Type Selector
- [ ] Photo Uploader
- [ ] Recipe Form
- [ ] Reel Uploader
- [ ] Text Post Editor
- [ ] Post Detail Screen
- [ ] Post Actions (like, comment, save, share)
- [ ] Comments Section
- [ ] Like/Comment/Save UI

**Acceptance:**
- Можно создать пост (фото/рецепт/текст)
- Можно создать рецепт с шагами и ингредиентами
- Можно лайкнуть/прокомментировать/сохранить пост
- Видны все детали поста
- Комментарии отображаются корректно

---

### ✅ Feed (Лента)

#### Backend
- [ ] GET /feed (персональная лента)
- [ ] GET /feed?type=reels
- [ ] Алгоритм ранжирования (rule-based)
- [ ] Кэширование ленты в Redis
- [ ] Пагинация (cursor-based)
- [ ] Fanout-on-write для малых авторов
- [ ] Fanout-on-read для больших авторов

#### Frontend
- [ ] Home Feed Screen
- [ ] Feed Item Component
- [ ] Infinite Scroll
- [ ] Pull to Refresh
- [ ] Reels Feed (вертикальная прокрутка)
- [ ] Lazy Loading изображений

**Acceptance:**
- Видна лента постов от подписок
- Новые посты подгружаются при прокрутке
- Лента ранжируется по релевантности
- Reels feed работает в вертикальном режиме

---

### ✅ Communities (Сообщества)

#### Backend
- [ ] POST /communities
- [ ] GET /communities/{id}
- [ ] PATCH /communities/{id}
- [ ] GET /communities/{id}/posts
- [ ] POST /communities/{id}/posts
- [ ] POST /communities/{id}/join
- [ ] DELETE /communities/{id}/join
- [ ] GET /communities/{id}/members
- [ ] POST /communities/{id}/members/{user_id}/role
- [ ] Автоматическое распространение постов сообщества

#### Frontend
- [ ] Community Page
- [ ] Community Header
- [ ] Community Tabs (Feed/About/Members)
- [ ] Create Community Screen
- [ ] Community Posts Feed
- [ ] Join/Leave кнопка
- [ ] Admin Panel для сообщества

**Acceptance:**
- Можно создать сообщество
- Можно присоединиться к сообществу
- Админ может публиковать от имени сообщества
- Посты сообщества видны в ленте участников

---

### ✅ Media Upload (Загрузка медиа)

#### Backend
- [ ] POST /uploads/init (presigned URL)
- [ ] POST /uploads/complete
- [ ] GET /uploads/{upload_id}/status
- [ ] Обработка изображений (resize, optimize)
- [ ] Очередь транс-кодинга видео
- [ ] FFmpeg workers
- [ ] Генерация thumbnails

#### Frontend
- [ ] Image Picker
- [ ] Video Picker
- [ ] Upload Progress Indicator
- [ ] Preview загруженных файлов

**Acceptance:**
- Можно загрузить изображение
- Можно загрузить видео
- Виден прогресс загрузки
- Изображения оптимизируются
- Видео обрабатывается и доступно для просмотра

---

### ✅ Moderation (Модерация)

#### Backend
- [ ] Авто-модерация (OpenAI API)
- [ ] Проверка текста на токсичность
- [ ] Проверка изображений (NSFW)
- [ ] Очередь модерации
- [ ] GET /moderation/pending
- [ ] POST /moderation/{id}/approve
- [ ] POST /moderation/{id}/reject
- [ ] Система жалоб

#### Frontend
- [ ] Admin Panel (web или в приложении)
- [ ] Moderation Queue View
- [ ] Approve/Reject UI
- [ ] Report Post UI

**Acceptance:**
- Подозрительные посты автоматически помечаются
- Админ видит очередь модерации
- Админ может одобрить/отклонить пост
- Пользователи могут пожаловаться на контент

---

### ✅ Analytics (Аналитика)

#### Backend
- [ ] Сбор событий (view, like, comment, etc.)
- [ ] GET /analytics/posts/{id}
- [ ] GET /analytics/profile
- [ ] Агрегация метрик
- [ ] Хранение событий

#### Frontend
- [ ] Analytics Screen для авторов
- [ ] Графики метрик
- [ ] Детальная статистика поста

**Acceptance:**
- Авторы видят метрики своих постов
- Видны просмотры, лайки, комментарии
- Есть графики по времени

---

### ✅ Notifications (Уведомления)

#### Backend
- [ ] Push уведомления (FCM/APNs)
- [ ] Email уведомления (опционально)
- [ ] GET /notifications
- [ ] POST /notifications/{id}/read
- [ ] Настройки уведомлений

#### Frontend
- [ ] Notifications Screen
- [ ] Push notifications setup
- [ ] Notification preferences

**Acceptance:**
- Приходят push уведомления о новых событиях
- Можно просмотреть все уведомления
- Можно настроить типы уведомлений

---

### ✅ H.A.N. Plus (Подписка)

#### Backend
- [ ] Интеграция с платежной системой (Stripe)
- [ ] POST /subscriptions/create
- [ ] GET /subscriptions/status
- [ ] POST /subscriptions/cancel
- [ ] Приоритет в ленте для Plus
- [ ] Offline кэш для Saved

#### Frontend
- [ ] Subscription Screen
- [ ] Payment Flow
- [ ] Plus Badge в профиле
- [ ] Offline Saved Recipes

**Acceptance:**
- Можно купить Plus подписку
- Plus пользователи видят меньше рекламы
- Сохраненные рецепты доступны оффлайн

---

## Тестирование

### Unit Tests
- [ ] Тесты для моделей
- [ ] Тесты для сервисов
- [ ] Тесты для API endpoints

### Integration Tests
- [ ] Тесты для полных flow (создание поста, лента)
- [ ] Тесты для модерации
- [ ] Тесты для подписок

### E2E Tests
- [ ] Тесты для критических путей пользователя
- [ ] Тесты для мобильного приложения

---

## Деплой

### Backend
- [ ] Настроить CI/CD
- [ ] Настроить staging окружение
- [ ] Настроить production окружение
- [ ] Настроить мониторинг
- [ ] Настроить логирование

### Frontend
- [ ] Настроить сборку для production
- [ ] Настроить App Store / Play Store
- [ ] Настроить OTA updates (CodePush)

---

## Документация

- [ ] API документация (Swagger/OpenAPI)
- [ ] README для разработчиков
- [ ] Архитектурная документация
- [ ] Руководство по деплою

---

**Последнее обновление:** 2025-01-XX

