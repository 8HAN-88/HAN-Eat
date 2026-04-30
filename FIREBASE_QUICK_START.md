# 🚀 Быстрый старт: Настройка Firebase за 5 минут

## 📍 Где скачать файлы Firebase

### 🔗 Прямая ссылка:
**Firebase Console:** https://console.firebase.google.com/

---

## 📱 Android: google-services.json

### Шаги:

1. **Откройте Firebase Console:**
   - https://console.firebase.google.com/
   - Войдите в Google аккаунт

2. **Создайте/выберите проект:**
   - Нажмите "Add project" или выберите существующий

3. **Добавьте Android приложение:**
   - На главной странице проекта нажмите иконку **Android** (или "Add app" → Android)

4. **Введите данные:**
   ```
   Android package name: com.example.han_eat
   ```
   - ⚠️ **ВАЖНО:** Используйте именно `com.example.han_eat` (с подчеркиванием)

5. **Скачайте файл:**
   - Нажмите кнопку **"Download google-services.json"**
   - Файл скачается на ваш компьютер

6. **Поместите файл:**
   - Скопируйте скачанный `google-services.json`
   - Вставьте в: `D:\HAN Eat 1\android\app\google-services.json`
   - ✅ Готово!

---

## 🍎 iOS: GoogleService-Info.plist

### Шаги:

1. **В том же Firebase проекте:**
   - На главной странице проекта нажмите иконку **iOS** (или "Add app" → iOS)

2. **Введите данные:**
   ```
   iOS bundle ID: com.example.hanEat
   ```
   - ⚠️ **ВАЖНО:** Используйте именно `com.example.hanEat` (без подчеркивания, с заглавной E)

3. **Скачайте файл:**
   - Нажмите кнопку **"Download GoogleService-Info.plist"**
   - Файл скачается на ваш компьютер

4. **Поместите файл:**
   - Скопируйте скачанный `GoogleService-Info.plist`
   - Вставьте в: `D:\HAN Eat 1\ios\Runner\GoogleService-Info.plist`

5. **Добавьте в Xcode (ВАЖНО!):**
   - Откройте `ios/Runner.xcworkspace` в Xcode
   - Перетащите `GoogleService-Info.plist` в папку "Runner"
   - Выберите "Copy items if needed" и "Add to targets: Runner"
   - ✅ Готово!

---

## ✅ Проверка

После скачивания файлов проверьте:

- [ ] `android/app/google-services.json` существует
- [ ] `ios/Runner/GoogleService-Info.plist` существует
- [ ] iOS файл добавлен в Xcode проект

---

## 🎯 Итоговые пути файлов:

```
D:\HAN Eat 1\
├── android\
│   └── app\
│       └── google-services.json          ← Сюда для Android
└── ios\
    └── Runner\
        └── GoogleService-Info.plist      ← Сюда для iOS
```

---

## 📚 Подробная инструкция

Если нужна более детальная инструкция с настройкой сервисов Firebase, смотрите:
- **FIREBASE_SETUP.md** - полная пошаговая инструкция

---

**Готово!** Теперь Firebase настроен! 🎉

