/// Слой видео как в Instagram: ролик только рисуется, жесты — у UI сверху.
class DomVideoTouchPolicy {
  const DomVideoTouchPolicy._();

  /// Как в IG: никакого DOM-щита с preventDefault над приложением.
  static const bool enableTouchShield = false;

  /// Как в IG: плеер не участвует в hit-test — лайк, свайп и табы всегда живые.
  static const bool videoIsVisualOnly = true;

  /// Пока ролик неактивен или вкладка скрыта — не крутить sync
  /// и не оставлять `<video>` в DOM (iOS иначе жрёт тапы на всех экранах).
  static bool shouldKeepFrameLoop({
    required bool active,
    required bool failed,
    required bool hasUrls,
    bool tickerEnabled = true,
  }) {
    return active && !failed && hasUrls && tickerEnabled;
  }

  /// Если Flutter-pane пропал или dispatch не прошёл — снять щит,
  /// иначе preventDefault съест все нажатия в PWA.
  static bool shouldFailOpen({
    required bool hostFound,
    required bool dispatched,
  }) {
    return !hostFound || !dispatched;
  }

  /// Не синхронизировать DOM 60 раз в секунду на каждом закэшированном видео.
  static const Duration minSyncGap = Duration(milliseconds: 48);

  static bool shouldSyncNow({
    required DateTime now,
    DateTime? lastSync,
    Duration gap = minSyncGap,
  }) {
    if (lastSync == null) return true;
    return !now.difference(lastSync).isNegative &&
        now.difference(lastSync) >= gap;
  }
}
