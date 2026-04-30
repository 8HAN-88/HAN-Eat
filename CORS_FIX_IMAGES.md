# ✅ Исправление CORS для изображений

## 🔍 Проблема:

**Ошибка в Flutter Web:**
```
❌ Image load error for https://img.spoonacular.com/recipes/640461-556x370.jpg: 
HTTP request failed, statusCode: 0
```

**Причина:** Flutter Web блокирует загрузку изображений с внешних доменов из-за CORS (Cross-Origin Resource Sharing).

## ✅ Решение:

Добавлен **прокси endpoint** на бэкенде, который:
1. Загружает изображения с Spoonacular
2. Отдает их с правильными CORS заголовками
3. Позволяет Flutter Web загружать изображения

### Бэкенд:

**Новый endpoint:** `GET /api/v1/recipes/image-proxy?url=...`

**Файл:** `backend/app/api/v1/recipes.py`

**Функционал:**
- Принимает URL изображения
- Проверяет, что это URL от Spoonacular (безопасность)
- Загружает изображение
- Возвращает с CORS заголовками:
  - `Access-Control-Allow-Origin: *`
  - `Access-Control-Allow-Methods: GET`
  - `Cache-Control: public, max-age=86400`

### Фронтенд:

**Файл:** `lib/widgets/modern_recipe_card.dart`

**Изменения:**
- Добавлена функция `_getProxyUrl()` для определения URL
- Для Spoonacular изображений используется прокси
- Для других изображений используется оригинальный URL
- Используется `ApiService.baseUrl` для правильного определения адреса бэкенда

## 🚀 Что делать:

1. **Перезапустите бэкенд:**
   ```powershell
   cd "D:\HAN Eat 1\backend"
   python run.py
   ```

2. **Перезапустите Flutter:**
   - Нажмите `R` для hot restart
   - Или перезапустите полностью

3. **Проверьте:**
   - Откройте Menu в приложении
   - Изображения должны загружаться
   - В консоли не должно быть ошибок CORS

## 🔍 Проверка:

**Проверьте прокси endpoint:**
```
http://localhost:5000/docs
```

**Вызовите:**
- `GET /api/v1/recipes/image-proxy?url=https://img.spoonacular.com/recipes/640461-556x370.jpg`

**Должно вернуть:**
- Изображение с правильными CORS заголовками

## ⚠️ Примечания:

- Прокси используется **только для Spoonacular изображений**
- Для других изображений используется оригинальный URL
- Прокси работает для всех платформ, но особенно важен для Flutter Web
- Изображения кэшируются на 24 часа

---

**Изображения теперь должны загружаться!** ✅

