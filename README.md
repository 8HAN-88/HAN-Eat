# 🍽️ HAN Eat

Приложение для поиска рецептов с AI-рекомендациями, сообществом и планированием питания.

## 🚀 Быстрый старт

### 1. Установка зависимостей

```bash
flutter pub get
```

### 2. Настройка окружения

Создайте файл `.env` в корне проекта:

```env
SPOONACULAR_API_KEY=ваш_api_ключ_здесь
```

Получите API ключ на [Spoonacular](https://spoonacular.com/food-api/console)

### 3. Настройка Firebase

- Android: Добавьте `google-services.json` в `android/app/`
- iOS: Добавьте `GoogleService-Info.plist` в `ios/Runner/`

### 4. Запуск бэкенд сервера

```bash
cd RecipeApp
python app.py
# или
python app_simple.py
```

Подробнее: [RecipeApp/README_SERVER.md](RecipeApp/README_SERVER.md)

### 5. Запуск приложения

```bash
flutter run
```

## 📱 Функции

- 🔍 Поиск рецептов по ингредиентам
- 🤖 AI-рекомендации
- ❤️ Избранное
- 📅 План питания
- 👥 Сообщество (загрузка видео)
- 🏷️ Категории рецептов
- 📝 История поиска
- 🛒 Список покупок
- 🔔 Уведомления

## 🏗️ Архитектура

- **State Management:** Riverpod
- **Navigation:** GoRouter
- **Локальное хранилище:** Hive, SharedPreferences
- **Backend:** Firebase (Auth, Firestore, Storage, Messaging)
- **API:** Spoonacular, собственный Python сервер

## 📚 Документация

- [MVP план](docs/MVP_plan.md)
- [Настройка категорий](CATEGORIES_SETUP.md)
- [Настройка плана питания](MEAL_PLAN_SETUP.md)
- [Улучшения дизайна](DESIGN_IMPROVEMENTS.md)
- [Оценка готовности](ASSESSMENT.md)

## 🧪 Тестирование

```bash
flutter test
```

## 📝 Лицензия

Private project
