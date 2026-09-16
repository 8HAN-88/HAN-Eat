/// Пороги холодного старта PWA: не ждать /health и /users/me перед UI.
class ColdStartPolicy {
  const ColdStartPolicy._();

  /// HTML не должен ждать /health, прежде чем грузить Flutter.
  static const bool htmlWaitsForHealthBeforeFlutter = false;

  /// Не сносить Cache API при первой неудаче: на 3G это убивает вход.
  static const bool wipeCachesOnFirstFlutterRetry = false;

  /// Восстановление профиля при старте — короткий таймаут.
  static const Duration webUsersMeTimeout = Duration(seconds: 2);

  /// Сколько HTML ждёт первый кадр Flutter, если сессия уже есть.
  static const Duration htmlFirstFrameTimeoutWithSession =
      Duration(seconds: 90);

  /// Deferred-чанк полного приложения не должен держать сплэш вечно.
  static const Duration webFullAppLibraryTimeout = Duration(seconds: 12);

  /// «Обновление…» из-за SSE — не дольше этого, дальше работаем с кэшем/поллингом.
  static const Duration updatingChromeMax = Duration(seconds: 8);
}
