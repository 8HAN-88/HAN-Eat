import '../core/config/legacy_firestore_config.dart';

/// Блокировка legacy Firestore-сервисов в release.
class LegacyFirestoreGuard {
  static void ensureEnabled() {
    if (LegacyFirestoreConfig.disabled) {
      throw UnsupportedError(
        'Legacy Firestore отключён в release. Используйте каналы и API V2.',
      );
    }
  }
}
