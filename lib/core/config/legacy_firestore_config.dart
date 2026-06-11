/// Синхронизация через Firestore (избранное, локальный meal plan, legacy community).
///
/// В release отключено — источник правды: Hive локально + FastAPI.
/// Включить вручную: `--dart-define=HANEAT_LEGACY_FIRESTORE=true`
class LegacyFirestoreConfig {
  static const bool _forceEnable = bool.fromEnvironment(
    'HANEAT_LEGACY_FIRESTORE',
    defaultValue: false,
  );

  /// Только с `--dart-define=HANEAT_LEGACY_FIRESTORE=true` (не включаем в debug на
  /// телефоне — Firestore при старте давал нестабильность / вылеты на iOS).
  static bool get enabled => _forceEnable;

  static bool get disabled => !enabled;
}
