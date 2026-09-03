/// Пороги для слабой сети: не ждать 429 минуту и быстрее считать API мёртвым.
class WeakNetPolicy {
  const WeakNetPolicy._();

  static const Duration mediaRateLimitMaxWait = Duration(seconds: 8);

  /// Фото и голосовые: не висеть минутами на одном PUT.
  static const Duration mediaUploadTimeout = Duration(seconds: 90);

  /// Видео / файлы больше и медленнее.
  static const Duration mediaUploadTimeoutLarge = Duration(seconds: 180);

  static const int webFailuresBeforeDown = 2;

  static bool isRetryableTransportError(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('too many requests') ||
        s.contains('rate_limit') ||
        s.contains('429') ||
        s.contains('502') ||
        s.contains('503') ||
        s.contains('504') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('timeoutexception') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('socket') ||
        s.contains('offline') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception');
  }

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
