# 🚀 Инструкция по запуску сервера RecipeApp

## 📋 Требования

- Python 3.8+
- API ключ от Spoonacular (https://spoonacular.com/food-api/console)

## 🔧 Установка зависимостей

### Вариант 1: Автоматическая установка (Windows)
```bash
# В папке RecipeApp/
install_dependencies.bat
```

### Вариант 2: Ручная установка
```bash
# В папке RecipeApp/
pip install -r requirements.txt
```

### Вариант 3: Базовые зависимости (без переводов)
```bash
pip install Flask Flask-Cors requests python-dotenv
```

## ⚙️ Настройка .env файла

Создайте файл `RecipeApp/.env` со следующим содержимым:

```
SPOONACULAR_API_KEY=ваш_api_ключ_здесь
HAN_DEFAULT_LANGUAGE=ru
HAN_DEFAULT_MODE=all
```

## 🚀 Запуск сервера

### Вариант 1: Полная версия (с переводами, если установлен googletrans)
```bash
python app.py
```

### Вариант 2: Упрощенная версия (без переводов)
```bash
python app_simple.py
```

**Рекомендация:** Если googletrans не установился, используйте `app_simple.py` - он работает без переводов, но все остальные функции работают.

## ✅ Проверка работы

После запуска сервера откройте в браузере:
```
http://127.0.0.1:5000/
```

Должен вернуться JSON:
```json
{
  "message": "RecipeApp API работает ✅",
  "translator": true/false,
  "langdetect": true/false
}
```

## 🧪 Тест поиска рецептов

```bash
curl -X POST http://127.0.0.1:5000/recipes \
  -H "Content-Type: application/json" \
  -d "{\"ingredients\": \"chicken\", \"mode\": \"all\", \"language\": \"en\"}"
```

## 📱 Запуск Flutter приложения

После запуска сервера, в корневой папке проекта:

```bash
flutter pub get
flutter run
```

## ⚠️ Решение проблем

### Ошибка: ModuleNotFoundError: No module named 'googletrans'
**Решение:** Используйте `app_simple.py` вместо `app.py`

### Ошибка: SPOONACULAR_API_KEY не найден
**Решение:** Проверьте что файл `.env` существует в папке `RecipeApp/` и содержит правильный API ключ

### Ошибка: Connection timeout
**Решение:** 
1. Проверьте интернет соединение
2. Увеличьте timeout в коде (уже установлено 30 секунд)
3. Проверьте что API ключ активен на Spoonacular

### Порт 5000 занят
**Решение:** Измените порт в `app.py` или `app_simple.py`:
```python
app.run(debug=True, host="127.0.0.1", port=5001)
```

И в Flutter (`lib/services/api_service.dart`):
```dart
static const String baseUrl = 'http://127.0.0.1:5001';
```

## 📝 Логи

Сервер выводит подробные логи:
- 🔍 Поиск рецептов
- 🌐 Запросы к Spoonacular API
- ✅ Успешные ответы
- ❌ Ошибки

Следите за логами для отладки!

