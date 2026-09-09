/// Слой видео как в Instagram: ролик только рисуется, жесты — у UI сверху.
class DomVideoTouchPolicy {
  const DomVideoTouchPolicy._();

  /// Как в IG: никакого DOM-щита с preventDefault над приложением.
  static const bool enableTouchShield = false;

  /// Как в IG: плеер не участвует в hit-test — лайк, свайп и табы всегда живые.
  static const bool videoIsVisualOnly = true;

  /// HtmlElementView на iPhone перехватывает тапы даже под IgnorePointer.
  static const bool allowHtmlElementViewVideo = false;

  /// Пока HTML-сплэш / первый кадр не отдали UI — не клеим DOM-видео.
  static bool uiInteractive = false;

  /// Вертикальная карточка ленты ~56% высоты. На iPhone даже такой
  /// `<video>` + дырка в canvas забирает тапы у всего приложения.
  static const double maxNonImmersiveCover = 0.40;

  /// Карточка ленты не должна становиться полноэкранным слоем при старте.
  static bool allowDomVideoAttach({
    required bool uiReady,
    required double videoWidth,
    required double videoHeight,
    required double viewWidth,
    required double viewHeight,
    bool fullscreenSurface = false,
  }) {
    if (!uiReady) return false;
    if (!_finitePositive(videoWidth) || !_finitePositive(videoHeight)) {
      return false;
    }
    if (!_finitePositive(viewWidth) || !_finitePositive(viewHeight)) {
      return false;
    }
    if (fullscreenSurface) return true;
    final cover = (videoWidth * videoHeight) / (viewWidth * viewHeight);
    return cover <= maxNonImmersiveCover;
  }

  static bool _finitePositive(double value) =>
      value.isFinite && value >= 2;

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
