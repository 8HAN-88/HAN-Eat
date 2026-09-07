/// Правила DOM-щита Safari: не жечь главный поток и не глотать тапы навсегда.
class DomVideoTouchPolicy {
  const DomVideoTouchPolicy._();

  /// Выключен: щит с preventDefault глушил все кнопки в iPhone PWA.
  static const bool enableTouchShield = false;

  /// Пока ролик неактивен, не крутить post-frame sync каждый кадр.
  static bool shouldKeepFrameLoop({
    required bool active,
    required bool failed,
    required bool hasUrls,
  }) {
    return active && !failed && hasUrls;
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
