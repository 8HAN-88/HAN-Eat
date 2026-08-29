/// Пороги для слабой сети: не ждать 429 минуту и быстрее считать API мёртвым.
class WeakNetPolicy {
  const WeakNetPolicy._();

  static const Duration mediaRateLimitMaxWait = Duration(seconds: 8);

  static const int webFailuresBeforeDown = 2;

  static Duration mediaRateLimitDelay({
    required Duration remaining,
    required Duration elapsed,
  }) {
    final left = mediaRateLimitMaxWait - elapsed;
    if (left <= Duration.zero) return Duration.zero;
    return remaining < left ? remaining : left;
  }

  static bool shouldStopRateLimitWait(Duration elapsed) =>
      !elapsed.isNegative && elapsed >= mediaRateLimitMaxWait;
}
