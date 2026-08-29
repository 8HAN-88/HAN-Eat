/// Свайп рилсов: меньше rebuild/dispose в кадре анимации.
class ReelsSwipePolicy {
  const ReelsSwipePolicy._();

  /// Не dispose-ить HTMLVideo во время флинга — Safari подвисает.
  static const Duration disposeAfterSettle = Duration(milliseconds: 280);

  static Duration neighborInitDelay({
    required int offsetFromCurrent,
    required bool isWeb,
  }) {
    if (offsetFromCurrent == 1) {
      return isWeb
          ? Duration.zero
          : const Duration(milliseconds: 180);
    }
    if (offsetFromCurrent == -1) {
      return isWeb
          ? const Duration(milliseconds: 160)
          : const Duration(milliseconds: 420);
    }
    if (offsetFromCurrent == 2) {
      return isWeb
          ? const Duration(milliseconds: 320)
          : const Duration(milliseconds: 760);
    }
    return const Duration(milliseconds: 400);
  }

  /// На PWA второй декодер (апгрейд 480→720) во время свайпа даёт лаг.
  static bool skipQualityUpgrade({required bool isWeb}) => isWeb;
}
