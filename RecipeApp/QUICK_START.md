# ⚡ Быстрый старт

## 1️⃣ Установи зависимости

```bash
cd RecipeApp
pip install Flask Flask-Cors requests python-dotenv
```

**Опционально** (для переводов):
```bash
pip install googletrans==4.0.0rc1 langdetect==1.0.9
```

## 2️⃣ Проверь .env файл

Убедись что в `RecipeApp/.env` есть:
```
SPOONACULAR_API_KEY=твой_ключ
```

## 3️⃣ Запусти сервер

**Если googletrans установлен:**
```bash
python app.py
```

**Если googletrans НЕ установлен (рекомендуется):**
```bash
python app_simple.py
```

## 4️⃣ Проверь работу

Открой: http://127.0.0.1:5000/

Должно вернуть: `{"message": "RecipeApp API работает ✅"}`

## 5️⃣ Запусти Flutter

В корневой папке проекта:
```bash
flutter run
```

## ✅ Готово!

Сервер работает! 🎉

