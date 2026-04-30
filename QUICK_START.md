# ⚡ Быстрый запуск всего приложения

## 🎯 Самый простой способ (1 команда):

### Windows (PowerShell):
```powershell
.\start_all.ps1
```

### Windows (CMD):
```cmd
start_all.bat
```

**Этот скрипт автоматически:**
1. ✅ Проверит Python и Flutter
2. ✅ Запустит бэкенд сервер в отдельном окне
3. ✅ Запустит Flutter приложение в браузере

---

## 📋 Ручной запуск (пошагово):

### Шаг 1: Откройте первый терминал для бэкенда

```bash
cd "D:\HAN Eat 1\RecipeApp"
python app_simple.py
```

**Должно появиться:**
```
 * Running on http://127.0.0.1:5000
```

**Оставьте это окно открытым!** ⚠️

### Шаг 2: Откройте второй терминал для Flutter

```bash
cd "D:\HAN Eat 1"
flutter run -d chrome
```

**Приложение откроется в браузере Chrome!** 🎉

---

## ✅ Что будет работать:

- ✅ Навигация между экранами
- ✅ Просмотр рецептов
- ✅ Поиск рецептов (через бэкенд)
- ✅ Рекомендации (через бэкенд)
- ✅ Избранное (локально)
- ✅ История поиска
- ✅ Категории
- ✅ План питания

---

## ⚠️ Если что-то не работает:

### Бэкенд не запускается:

**Ошибка: "ModuleNotFoundError"**
```bash
cd RecipeApp
pip install flask flask-cors requests python-dotenv
```

**Ошибка: "Port 5000 already in use"**
- Закройте другое приложение на порту 5000
- Или измените порт в `app_simple.py`

### Flutter не запускается:

**Ошибка: "No devices found"**
```bash
flutter run -d chrome  # Для браузера
flutter run -d windows # Для Windows
```

**Ошибка: "Build failed"**
```bash
flutter clean
flutter pub get
flutter run -d chrome
```

---

## 🎯 Проверка что всё работает:

1. **Бэкенд сервер:**
   - Откройте в браузере: http://127.0.0.1:5000
   - Должен вернуться JSON: `{"message": "RecipeApp API работает ✅"}`

2. **Flutter приложение:**
   - Должен открыться главный экран
   - Навигация должна работать
   - Поиск рецептов должен работать

---

## 📝 Полная настройка (опционально):

### Для Spoonacular API:

1. Получите ключ: https://spoonacular.com/food-api/console
2. Создайте `RecipeApp/.env`:
   ```
   SPOONACULAR_API_KEY=ваш_ключ
   ```

### Для Firebase:

См. `FIREBASE_SETUP.md`

---

**Готово!** Теперь вы знаете как запустить всё приложение! 🚀

