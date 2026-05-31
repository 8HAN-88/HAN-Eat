import 'package:flutter/foundation.dart';

import 'dotenv_safe.dart';

/// OAuth client IDs для Google Sign-In (Firebase / Google Cloud Console).
///
/// Задайте в корневом `.env` и/или через `--dart-define`:
/// - `GOOGLE_WEB_CLIENT_ID` — Web client (serverClientId, aud для backend)
/// - `GOOGLE_IOS_CLIENT_ID` — iOS client (нужен, если нет GoogleService-Info.plist)
///
/// Backend: `GOOGLE_OAUTH_CLIENT_IDS` = тот же Web client ID.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const _webFromDefine = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _iosFromDefine = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static String? _trim(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static String? get webClientId =>
      _trim(_webFromDefine) ?? dotenvString('GOOGLE_WEB_CLIENT_ID');

  static String? get iosClientId =>
      _trim(_iosFromDefine) ?? dotenvString('GOOGLE_IOS_CLIENT_ID');

  /// URL scheme для `ios/Runner/Info.plist` → `CFBundleURLSchemes`.
  static String? get iosReversedClientId {
    final id = iosClientId;
    if (id == null || !id.endsWith('.apps.googleusercontent.com')) {
      return null;
    }
    final prefix = id.substring(0, id.length - '.apps.googleusercontent.com'.length);
    return 'com.googleusercontent.apps.$prefix';
  }

  static bool get isConfigured => webClientId != null;

  static bool get needsIosClientId {
    if (kIsWeb) return false;
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  /// Бросает [StateError] с шагами настройки, если Web client ID не задан.
  static void ensureConfigured() {
    if (isConfigured) return;
    throw StateError(_setupMessage);
  }

  static String get _setupMessage => '''
Google Sign-In не настроен.

1. Firebase Console → проект han-eat → Authentication → включите Google.
2. Скачайте обновлённые `android/app/google-services.json` и `ios/Runner/GoogleService-Info.plist`.
3. В корневой `.env` добавьте:
   GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
   GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
4. В `backend/.env`: GOOGLE_OAUTH_CLIENT_IDS=<тот же Web client ID>
5. iOS: в Info.plist добавьте URL scheme (REVERSED_CLIENT_ID из plist или из iosReversedClientId).
6. Перезапустите backend и приложение.''';

  static String? missingPlatformHint() {
    if (!isConfigured) return null;
    if (needsIosClientId && iosClientId == null) {
      final scheme = iosReversedClientId;
      return 'Для iOS укажите GOOGLE_IOS_CLIENT_ID в .env'
          '${scheme != null ? ' и URL scheme $scheme в Info.plist' : ''}, '
          'либо добавьте GoogleService-Info.plist в ios/Runner/.';
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'На Android обновите google-services.json после включения Google в Firebase '
          '(в файле должен быть непустой oauth_client).';
    }
    return null;
  }
}
