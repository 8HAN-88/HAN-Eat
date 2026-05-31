import 'package:flutter/foundation.dart';

/// Синхронизация через Firestore (избранное, локальный meal plan, legacy community).
///
/// В release отключено — источник правды: Hive локально + FastAPI.
/// Включить вручную: `--dart-define=HANEAT_LEGACY_FIRESTORE=true`
class LegacyFirestoreConfig {
  static const bool _forceEnable = bool.fromEnvironment(
    'HANEAT_LEGACY_FIRESTORE',
    defaultValue: false,
  );

  static bool get enabled => kDebugMode || _forceEnable;

  static bool get disabled => !enabled;
}
