# 📋 Инструкция по настройке HAN Eat

## ✅ Что уже сделано автоматически

- ✅ Добавлена зависимость `go_router` в `pubspec.yaml`
- ✅ Обновлен `README.md`
- ✅ Создан файл оценки `ASSESSMENT.md`

## 🔧 Что нужно сделать вручную

### 1. Создать файл `.env`

Создайте файл `.env` в корне проекта (`D:\HAN Eat 1\.env`):

```env
SPOONACULAR_API_KEY=ваш_api_ключ_здесь
```

**Как получить API ключ:**
1. Зайдите на https://spoonacular.com/food-api/console
2. Зарегистрируйтесь или войдите
3. Создайте новый API ключ
4. Скопируйте ключ в файл `.env`

### 2. Настроить Firebase

#### Для Android:

1. **Создайте проект в Firebase Console:**
   - Зайдите на https://console.firebase.google.com/
   - Создайте новый проект или выберите существующий
   - Добавьте Android приложение с package name: `com.example.han_eat`

2. **Скачайте файл `google-services.json`:**
   - В Firebase Console перейдите в Project Settings
   - Скачайте `google-services.json`
   - Скопируйте его в `android/app/google-services.json`

3. **Добавьте плагин в `android/build.gradle.kts`:**
   ```kotlin
   plugins {
       id("com.android.application") version "8.1.0" apply false
       id("com.android.library") version "8.1.0" apply false
       id("org.jetbrains.kotlin.android") version "1.9.0" apply false
       id("com.google.gms.google-services") version "4.4.0" apply false  // <-- добавьте эту строку
   }
   ```

4. **Добавьте плагин в `android/app/build.gradle.kts`:**
   ```kotlin
   plugins {
       id("com.android.application")
       id("kotlin-android")
       id("dev.flutter.flutter-gradle-plugin")
       id("com.google.gms.google-services")  // <-- добавьте эту строку
   }
   ```

#### Для iOS:

1. **Добавьте iOS приложение в Firebase Console:**
   - В Firebase Console добавьте iOS приложение
   - Bundle ID: `com.example.hanEat` (или ваш)

2. **Скачайте файл `GoogleService-Info.plist`:**
   - Скачайте `GoogleService-Info.plist`
   - Скопируйте его в `ios/Runner/GoogleService-Info.plist`

3. **Добавьте файл в Xcode:**
   - Откройте `ios/Runner.xcworkspace` в Xcode
   - Перетащите `GoogleService-Info.plist` в проект Runner
   - Убедитесь что файл добавлен в target

### 3. Запустить бэкенд сервер

```bash
cd RecipeApp
python app.py
```

Или если есть проблемы с зависимостями:

```bash
cd RecipeApp
python app_simple.py
```

**Важно:** Сервер должен быть запущен на `http://127.0.0.1:5000` (или измените URL в `lib/services/api_service.dart`)

### 4. Установить зависимости Flutter

```bash
flutter pub get
```

### 5. Сгенерировать код (если нужно)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 🚀 Запуск приложения

### Android:
```bash
flutter run
```

### iOS:
```bash
flutter run -d ios
```

### Web:
```bash
flutter run -d chrome
```

## ⚠️ Решение проблем

### Ошибка: "SPOONACULAR_API_KEY not set"
**Решение:** Создайте файл `.env` с вашим API ключом

### Ошибка: "Firebase init error"
**Решение:** 
- Убедитесь что файлы `google-services.json` (Android) и `GoogleService-Info.plist` (iOS) на месте
- Проверьте что плагин `com.google.gms.google-services` добавлен в `build.gradle.kts`

### Ошибка: "Connection timeout" при запросах к API
**Решение:**
- Убедитесь что бэкенд сервер запущен
- Проверьте URL в `lib/services/api_service.dart` (для эмулятора: `http://10.0.2.2:5000`, для реального устройства: `http://YOUR_IP:5000`)

### Ошибка: "go_router not found"
**Решение:** Запустите `flutter pub get`

## 📝 Чек-лист готовности

- [ ] Файл `.env` создан с `SPOONACULAR_API_KEY`
- [ ] `google-services.json` добавлен в `android/app/`
- [ ] `GoogleService-Info.plist` добавлен в `ios/Runner/`
- [ ] Плагин `com.google.gms.google-services` добавлен в `build.gradle.kts`
- [ ] Бэкенд сервер запущен
- [ ] `flutter pub get` выполнен
- [ ] Приложение запускается без ошибок

## 🎯 После настройки

Приложение готово к использованию! Все основные функции должны работать:
- ✅ Поиск рецептов
- ✅ Избранное
- ✅ План питания
- ✅ Сообщество
- ✅ Уведомления
