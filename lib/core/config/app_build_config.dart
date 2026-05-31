import 'package:flutter/foundation.dart';

import 'dotenv_safe.dart';

/// Параметры сборки через `--dart-define` или корневой `.env` (`HANEAT_API_BASE`).
///
/// Примеры:
/// `flutter run --dart-define=HANEAT_API_BASE=https://api.haneat.app`
/// `flutter run --dart-define=APP_ENV=staging`
abstract final class AppBuildConfig {
  static const String _apiBase = String.fromEnvironment(
    'HANEAT_API_BASE',
    defaultValue: '',
  );

  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );

  /// development | staging | production
  static String get environment {
    if (_appEnv.isNotEmpty) return _appEnv;
    if (kReleaseMode) return 'production';
    return 'development';
  }

  static bool get isProduction => environment == 'production';
  static bool get isStaging => environment == 'staging';

  static String? _apiBaseFromDotenv() => dotenvString('HANEAT_API_BASE');

  /// Корень API без `/api/v1`.
  static String get apiBaseRoot {
    if (_apiBase.isNotEmpty) return _apiBase;
    final fromDotenv = _apiBaseFromDotenv();
    if (fromDotenv != null) return fromDotenv;
    if (kReleaseMode) {
      return 'https://api.haneat.app';
    }
    // По умолчанию — Timeweb API. Локальный backend:
    // flutter run --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001
    return 'https://api.haneat.app';
  }

  static bool get apiBaseWasConfigured =>
      _apiBase.isNotEmpty || _apiBaseFromDotenv() != null;
}
