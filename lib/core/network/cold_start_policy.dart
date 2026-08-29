/// Пороги холодного старта PWA: не ждать /health и /users/me перед UI.
class ColdStartPolicy {
  const ColdStartPolicy._();

  /// HTML не должен ждать /health, прежде чем грузить Flutter.
  static const bool htmlWaitsForHealthBeforeFlutter = false;

  /// Восстановление профиля при старте — короткий таймаут.
  static const Duration webUsersMeTimeout = Duration(seconds: 2);
}
