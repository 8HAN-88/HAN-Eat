# 🔥 Пошаговая инструкция по настройке Firebase

## 📋 Шаг 1: Создание проекта в Firebase

1. **Зайдите на Firebase Console:**
   - Откройте https://console.firebase.google.com/
   - Войдите в свой Google аккаунт

2. **Создайте новый проект:**
   - Нажмите "Add project" (Добавить проект)
   - Введите название проекта (например: "HAN Eat")
   - Нажмите "Continue"
   - (Опционально) Отключите Google Analytics или включите - на ваше усмотрение
   - Нажмите "Create project" (Создать проект)
   - Дождитесь создания проекта и нажмите "Continue"

## 📱 Шаг 2: Добавление Android приложения

1. **В Firebase Console:**
   - На главной странице проекта нажмите на иконку Android (или "Add app" → Android)

2. **Заполните форму:**
   - **Android package name:** `com.example.han_eat`
     - ⚠️ ВАЖНО: Это должно точно совпадать с `applicationId` в `android/app/build.gradle.kts`
     - ✅ Текущее значение в проекте: `com.example.han_eat` (уже правильно!)
   - **App nickname (optional):** HAN Eat Android
   - **Debug signing certificate SHA-1 (optional):** можно пропустить для начала
   - Нажмите "Register app"

3. **Скачайте `google-services.json`:**
   - На следующем экране нажмите кнопку "Download google-services.json"
   - Файл скачается на ваш компьютер

4. **Поместите файл в проект:**
   - Скопируйте скачанный `google-services.json`
   - Вставьте его в папку `android/app/` (полный путь: `D:\HAN Eat 1\android\app\google-services.json`)
   - ⚠️ Убедитесь что файл называется именно `google-services.json` (без дополнительных цифр или символов)

5. **Завершите настройку:**
   - В Firebase Console нажмите "Next" → "Next" → "Continue to console"
   - Android приложение добавлено!

## 🍎 Шаг 3: Добавление iOS приложения

1. **В Firebase Console:**
   - На главной странице проекта нажмите на иконку iOS (или "Add app" → iOS)

2. **Заполните форму:**
   - **iOS bundle ID:** `com.example.hanEat`
     - ⚠️ ВАЖНО: Это должно совпадать с Bundle Identifier в Xcode
     - ✅ Текущее значение в проекте: `com.example.hanEat` (уже правильно!)
   - **App nickname (optional):** HAN Eat iOS
   - **App Store ID (optional):** можно пропустить
   - Нажмите "Register app"

3. **Скачайте `GoogleService-Info.plist`:**
   - На следующем экране нажмите кнопку "Download GoogleService-Info.plist"
   - Файл скачается на ваш компьютер

4. **Поместите файл в проект:**
   - Скопируйте скачанный `GoogleService-Info.plist`
   - Вставьте его в папку `ios/Runner/` (полный путь: `D:\HAN Eat 1\ios\Runner\GoogleService-Info.plist`)

5. **Добавьте файл в Xcode (ВАЖНО!):**
   - Откройте `ios/Runner.xcworkspace` в Xcode (НЕ .xcodeproj!)
   - В левой панели найдите папку "Runner"
   - Перетащите `GoogleService-Info.plist` в папку "Runner"
   - В диалоге выберите:
     - ✅ "Copy items if needed"
     - ✅ "Add to targets: Runner"
   - Нажмите "Finish"

6. **Завершите настройку:**
   - В Firebase Console нажмите "Next" → "Next" → "Continue to console"
   - iOS приложение добавлено!

## ✅ Шаг 4: Проверка правильности настройки

### Для Android:
- [ ] Файл `android/app/google-services.json` существует
- [ ] Package name в Firebase совпадает с `applicationId` в `build.gradle.kts`
- [ ] Плагин `com.google.gms.google-services` добавлен в `android/app/build.gradle.kts` (уже сделано)

### Для iOS:
- [ ] Файл `ios/Runner/GoogleService-Info.plist` существует
- [ ] Файл добавлен в Xcode проект
- [ ] Bundle ID в Firebase совпадает с Bundle Identifier в Xcode

## 🔧 Шаг 5: Настройка Firebase сервисов

После добавления приложений, включите нужные сервисы в Firebase Console:

1. **Authentication (Аутентификация):**
   - В боковом меню выберите "Authentication"
   - Нажмите "Get started"
   - Включите "Email/Password" и "Google" (Sign-in method)

2. **Firestore Database:**
   - В боковом меню выберите "Firestore Database"
   - Нажмите "Create database"
   - Выберите "Start in test mode" (для разработки)
   - Выберите регион (ближайший к вам)
   - Нажмите "Enable"

3. **Storage:**
   - В боковом меню выберите "Storage"
   - Нажмите "Get started"
   - Выберите "Start in test mode"
   - Выберите регион
   - Нажмите "Done"

4. **Cloud Messaging (для уведомлений):**
   - В боковом меню выберите "Cloud Messaging"
   - Сервис уже включен по умолчанию

## 📝 Важные замечания

### Package Name / Bundle ID

**Android:**
- Текущий package name: `com.example.han_eat`
- Проверьте в `android/app/build.gradle.kts`: `applicationId = "com.example.han_eat"`
- ⚠️ Если вы измените package name, нужно будет обновить его и в Firebase

**iOS:**
- Текущий Bundle ID: `com.example.hanEat` (обычно)
- Проверьте в Xcode: Runner → General → Bundle Identifier
- ⚠️ Если вы измените Bundle ID, нужно будет обновить его и в Firebase

### Безопасность (для продакшена)

После тестирования обязательно:
1. Настройте правила безопасности Firestore
2. Настройте правила безопасности Storage
3. Включите App Check для защиты от злоупотреблений

## 🚀 После настройки

1. **Установите зависимости:**
   ```bash
   flutter pub get
   ```

2. **Проверьте что файлы на месте:**
   - `android/app/google-services.json` ✅
   - `ios/Runner/GoogleService-Info.plist` ✅

3. **Запустите приложение:**
   ```bash
   flutter run
   ```

## ❓ Решение проблем

### Ошибка: "google-services.json not found"
- Убедитесь что файл находится именно в `android/app/google-services.json`
- Проверьте что файл не переименован

### Ошибка: "FirebaseApp not initialized"
- Проверьте что `google-services.json` правильно добавлен
- Убедитесь что плагин `com.google.gms.google-services` в `build.gradle.kts`
- Выполните `flutter clean && flutter pub get`

### Ошибка: "Bundle ID mismatch" (iOS)
- Проверьте Bundle ID в Xcode и в Firebase Console
- Они должны точно совпадать

## 📚 Дополнительные ресурсы

- [Официальная документация Firebase для Flutter](https://firebase.flutter.dev/)
- [Настройка Firebase для Android](https://firebase.google.com/docs/android/setup)
- [Настройка Firebase для iOS](https://firebase.google.com/docs/ios/setup)

---

**Готово!** После выполнения всех шагов Firebase будет настроен и готов к использованию. 🎉

