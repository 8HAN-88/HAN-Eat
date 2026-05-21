# TestFlight и Internal Testing

## Предусловия

Запустите автоматический чеклист:

```bash
./scripts/pre_testflight_check.sh
```

- [ ] Apple Developer Program (Team ID в Xcode)
- [ ] Bundle ID `com.haneat.app` в App Store Connect
- [ ] `ios/Runner/GoogleService-Info.plist` (Firebase)
- [ ] `android/key.properties` для release (Android — Internal testing в Play Console)
- [ ] Backend: `./scripts/smoke_launch.sh https://api.haneat.app` — exit 0

## iOS: сборка и загрузка

```bash
# 1. Версия в pubspec.yaml (version: x.y.z+build)
flutter pub get

# 2. Release IPA
./scripts/build_ios_release.sh https://api.haneat.app

# 3. Загрузка в App Store Connect
open build/ios/archive/Runner.xcarchive
# Xcode → Distribute App → App Store Connect → Upload
# Или: xcrun altool / Transporter.app с build/ios/ipa/*.ipa
```

### Подпись (обязательно для IPA)

Нужен сертификат **Apple Distribution** (или автоматическая подпись в Xcode с платным Apple Developer).

Если `flutter build ipa` падает с `No signing certificate "iOS Distribution" found`:

1. Xcode → **Settings** → **Accounts** → ваш Apple ID → **Manage Certificates** → **+** → **Apple Distribution**
2. Или: **open build/ios/archive/Runner.xcarchive** → **Distribute App** → App Store Connect (Xcode создаст профиль)

Архив без IPA уже лежит в `build/ios/archive/Runner.xcarchive` — его можно загрузить из Xcode.

### Crashlytics (символы)

Фаза **Upload Crashlytics Symbols** уже в `Runner.xcodeproj` (после `pod install` с `firebase_crashlytics`).  
Включите Crashlytics в Firebase Console после первой загрузки билда.

## App Store Connect

1. **My Apps** → HAN Eat → **TestFlight**
2. Дождитесь обработки билда (15–60 мин)
3. **Compliance**: экспорт шифрования — обычно «No» (только HTTPS)
4. **Internal Testing** → добавьте тестеров (до 100, без review)
5. **External Testing** → заполните «What to Test», отправьте на Beta Review

## Что проверить тестерам

См. `docs/LAUNCH_SMOKE.md` (ручной чеклист Flutter).

Минимум:

- Гость: лента без входа
- Регистрация / вход
- Канал + пост с фото
- Подписка (ЮKassa) → возврат `haneat://subscription/success`
- AI meal plan (free: лимиты и cooldown)

## Android Internal testing

```bash
./scripts/build_android_release.sh https://api.haneat.app
# Play Console → Internal testing → загрузить AAB из build/app/outputs/bundle/release/
```

## Staging-сборка (до prod)

```bash
./scripts/build_staging_ios.sh https://staging-api.haneat.app
```
