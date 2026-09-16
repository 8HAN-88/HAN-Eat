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

  test('web reads fail over to cache instead of retrying for a minute', () {
    expect(WeakNetPolicy.webReadTimeout.inSeconds, lessThanOrEqualTo(6));
    expect(WeakNetPolicy.webReadRetries, lessThanOrEqualTo(1));
    expect(WeakNetPolicy.webSharedAttempts, lessThanOrEqualTo(2));
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
}
