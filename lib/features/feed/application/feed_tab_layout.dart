/// Одна домашняя лента (подписки) + рилсы. Старые 3 вкладки мигрируем.
class FeedTabLayout {
  const FeedTabLayout._();

  static const int home = 0;
  static const int reels = 1;
  static const int count = 2;

  static const labels = ['Лента', 'Рилсы'];

  /// v1: 0 подписки, 1 рекомендации, 2 рилсы → v2: 0 лента, 1 рилсы.
  static int migrateStoredIndex(int stored, {required bool isV2}) {
    if (isV2) return stored.clamp(0, reels);
    if (stored == 2) return reels;
    return home;
  }

  static bool isReels(int index) => index == reels;
}
