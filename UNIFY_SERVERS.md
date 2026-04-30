# Объединение двух серверов в один

## 🔍 Проблема:

У вас есть **два сервера**, которые пытаются работать на одном порту 5000:

1. **Старый Flask сервер** (`RecipeApp/app.py`):
   - Порт: 5000
   - `.env` файл: `RecipeApp/.env` (с `SPOONACULAR_API_KEY`)
   - Endpoints: `/recipes`, `/recommendations`, `/analyze`, `/settings`, `/favorites`, `/history`

2. **Новый FastAPI бэкенд** (`backend/run.py`):
   - Порт: 5000
   - `.env` файл: `backend/.env` (с настройками БД, JWT и т.д.)
   - Endpoints: `/api/v1/auth/*`, `/api/v1/posts/*`, `/recommendations` (уже добавлен)

**Проблема:** Только один сервер может работать на порту 5000 одновременно!

## ✅ Решение: Объединить всё в FastAPI бэкенд

### Шаг 1: Добавить SPOONACULAR_API_KEY в FastAPI

Я уже добавил `SPOONACULAR_API_KEY` в `backend/app/core/config.py`.

**Теперь добавьте ключ в `backend/.env`:**

```env
SPOONACULAR_API_KEY=ваш_api_ключ_здесь
```

### Шаг 2: Перенести endpoints из Flask в FastAPI

Фронтенд использует следующие endpoints из Flask:

✅ **Уже добавлено:**
- `GET /recommendations` - рекомендации

❌ **Нужно добавить:**
- `POST /recipes` - поиск рецептов
- `POST /analyze` - анализ фото
- `GET /settings` - получение настроек
- `POST /settings` - обновление настроек
- `GET /favorites` - избранное
- `POST /favorites` - добавить в избранное
- `DELETE /favorites/{id}` - удалить из избранного
- `GET /history` - история поиска
- `DELETE /history` - очистить историю

### Шаг 3: Обновить фронтенд (если нужно)

После переноса всех endpoints, фронтенд будет работать только с FastAPI бэкендом.

## 🚀 Временное решение (пока endpoints не перенесены):

Если нужно, чтобы всё работало прямо сейчас:

### Вариант 1: Запустить Flask на другом порту

1. Измените порт в `RecipeApp/app.py`:
   ```python
   app.run(debug=True, host="127.0.0.1", port=5001)  # Изменить на 5001
   ```

2. Обновите `lib/services/api_service.dart`:
   ```dart
   static String get baseUrl {
     // Для рецептов используем Flask на 5001
     return 'http://localhost:5001';
   }
   ```

3. Оставьте `AuthService` с портом 5000 для FastAPI:
   ```dart
   static const String baseUrl = 'http://localhost:5000/api/v1';
   ```

### Вариант 2: Использовать только FastAPI (рекомендуется)

1. Добавьте `SPOONACULAR_API_KEY` в `backend/.env`
2. Запустите только FastAPI бэкенд:
   ```powershell
   cd "D:\HAN Eat 1\backend"
   python run.py
   ```
3. Остановите Flask сервер (если запущен)

**Пока не все endpoints перенесены, некоторые функции могут не работать.**

## 📋 План переноса endpoints:

1. ✅ `/recommendations` - уже добавлен
2. ⏳ `/recipes` - поиск рецептов (нужно добавить)
3. ⏳ `/analyze` - анализ фото (нужно добавить)
4. ⏳ `/settings` - настройки (нужно добавить)
5. ⏳ `/favorites` - избранное (можно использовать локальное хранилище)
6. ⏳ `/history` - история (можно использовать локальное хранилище)

## 🎯 Рекомендация:

**Лучше всего:** Перенести все endpoints в FastAPI и использовать один сервер. Это займет время, но будет более правильное решение.

**Быстрое решение:** Запустить Flask на порту 5001 для рецептов, а FastAPI на 5000 для аутентификации.

---

**Текущий статус:** Я добавил `SPOONACULAR_API_KEY` в конфигурацию FastAPI. Теперь нужно:
1. Добавить ключ в `backend/.env`
2. Решить: перенести все endpoints или использовать два порта

