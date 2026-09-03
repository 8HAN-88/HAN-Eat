import '../../../core/network/weak_net_policy.dart';

/// Как держать фото и голосовые в очереди на слабой сети (как текст).
class MediaSendPolicy {
  const MediaSendPolicy._();

  static const int maxAttempts = 8;

  static const Duration unreachablePoll = Duration(seconds: 4);

  static Duration uploadTimeout({required bool largeFile}) => largeFile
      ? WeakNetPolicy.mediaUploadTimeoutLarge
      : WeakNetPolicy.mediaUploadTimeout;

  static bool isRetryableNetworkError(Object error) =>
      WeakNetPolicy.isRetryableTransportError(error);

  /// Не снимать с очереди: API мёртв или это сеть/таймаут/429.
  /// Failed-bubble только для звёзд, 400, авторизации и т.п.
  static bool shouldKeepQueued({
    required Object error,
    required bool apiReachable,
  }) {
    if (!apiReachable) return true;
    return isRetryableNetworkError(error);
  }

  static int retryWaitSeconds({
    required int attempts,
    required bool apiReachable,
  }) {
    if (!apiReachable) return unreachablePoll.inSeconds;
    return (2 * attempts.clamp(1, 10)).clamp(2, 20);
  }
}
