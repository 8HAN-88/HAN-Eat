import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/reels/application/dom_video_touch_policy.dart';
import 'package:han_eat/widgets/web_dom_video_layer.dart';

void main() {
  test('touch shield stays off so PWA buttons keep working', () {
    expect(DomVideoTouchPolicy.enableTouchShield, isFalse);
  });

  test('inactive or failed hosts stop the per-frame sync loop', () {
    expect(
      DomVideoTouchPolicy.shouldKeepFrameLoop(
        active: true,
        failed: false,
        hasUrls: true,
      ),
      isTrue,
    );
    expect(
      DomVideoTouchPolicy.shouldKeepFrameLoop(
        active: false,
        failed: false,
        hasUrls: true,
      ),
      isFalse,
    );
    expect(
      DomVideoTouchPolicy.shouldKeepFrameLoop(
        active: true,
        failed: true,
        hasUrls: true,
      ),
      isFalse,
    );
    expect(
      DomVideoTouchPolicy.shouldKeepFrameLoop(
        active: true,
        failed: false,
        hasUrls: false,
      ),
      isFalse,
    );
  });

  test('missing Flutter host or failed dispatch fail-opens the shield', () {
    expect(
      DomVideoTouchPolicy.shouldFailOpen(hostFound: false, dispatched: false),
      isTrue,
    );
    expect(
      DomVideoTouchPolicy.shouldFailOpen(hostFound: true, dispatched: false),
      isTrue,
    );
    expect(
      DomVideoTouchPolicy.shouldFailOpen(hostFound: true, dispatched: true),
      isFalse,
    );
  });

  test('DOM sync is throttled so cached videos cannot pin the UI thread', () {
    expect(
      DomVideoTouchPolicy.minSyncGap.inMilliseconds,
      greaterThanOrEqualTo(32),
    );
    final now = DateTime.utc(2026, 9, 7, 14, 30);
    expect(
      DomVideoTouchPolicy.shouldSyncNow(now: now, lastSync: null),
      isTrue,
    );
    expect(
      DomVideoTouchPolicy.shouldSyncNow(
        now: now,
        lastSync: now.subtract(const Duration(milliseconds: 10)),
      ),
      isFalse,
    );
    expect(
      DomVideoTouchPolicy.shouldSyncNow(
        now: now,
        lastSync: now.subtract(const Duration(milliseconds: 80)),
      ),
      isTrue,
    );
  });

  test('stuck shield release is a no-op off web', () {
    expect(() => WebDomVideoLayer.releaseStuckTouchShield(), returnsNormally);
  });
}
