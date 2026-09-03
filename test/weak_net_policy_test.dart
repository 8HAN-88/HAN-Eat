import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/network/weak_net_policy.dart';

void main() {
  test('media 429 wait is capped at 8 seconds', () {
    expect(
      WeakNetPolicy.mediaRateLimitDelay(
        remaining: const Duration(seconds: 60),
        elapsed: Duration.zero,
      ),
      WeakNetPolicy.mediaRateLimitMaxWait,
    );
    expect(
      WeakNetPolicy.shouldStopRateLimitWait(const Duration(seconds: 8)),
      isTrue,
    );
    expect(
      WeakNetPolicy.shouldStopRateLimitWait(const Duration(seconds: 3)),
      isFalse,
    );
  });

  test('remaining slice shrinks as time passes', () {
    expect(
      WeakNetPolicy.mediaRateLimitDelay(
        remaining: const Duration(seconds: 2),
        elapsed: const Duration(seconds: 7),
      ),
      const Duration(seconds: 1),
    );
    expect(
      WeakNetPolicy.mediaRateLimitDelay(
        remaining: const Duration(seconds: 30),
        elapsed: const Duration(seconds: 9),
      ),
      Duration.zero,
    );
  });

  test('transport errors include timeout and 502', () {
    expect(
      WeakNetPolicy.isRetryableTransportError(
        Exception('TimeoutException: upload'),
      ),
      isTrue,
    );
    expect(
      WeakNetPolicy.isRetryableTransportError(Exception('502 Bad Gateway')),
      isTrue,
    );
    expect(
      WeakNetPolicy.mediaUploadTimeout,
      const Duration(seconds: 90),
    );
  });
}
