import 'package:flutter/foundation.dart';

/// Глобальная пауза после HTTP 429, чтобы не усиливать rate limit.
class ApiRateLimitBackoff {
  ApiRateLimitBackoff._();

  static DateTime? _blockedUntil;

  static bool get isActive {
    final until = _blockedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _blockedUntil = null;
    return false;
  }

  static Duration? get remaining {
    final until = _blockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    if (left.isNegative) {
      _blockedUntil = null;
      return null;
    }
    return left;
  }

  static void register({int retryAfterSeconds = 60}) {
    final sec = retryAfterSeconds.clamp(5, 120);
    _blockedUntil = DateTime.now().add(Duration(seconds: sec));
    if (kDebugMode) {
      debugPrint('ApiRateLimitBackoff: pause ${sec}s');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _blockedUntil = null;
  }
}
