import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/reels/application/dom_video_touch_policy.dart';
import 'package:han_eat/widgets/web_dom_video_layer.dart';

void main() {
  test('Instagram-style: video is visual-only, Flutter owns gestures', () {
    expect(DomVideoTouchPolicy.enableTouchShield, isFalse);
    expect(DomVideoTouchPolicy.videoIsVisualOnly, isTrue);
    expect(DomVideoTouchPolicy.allowHtmlElementViewVideo, isFalse);
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
    expect(
      DomVideoTouchPolicy.shouldKeepFrameLoop(
        active: true,
        failed: false,
        hasUrls: true,
        tickerEnabled: false,
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

  test('DOM video does not attach before UI is interactive', () {
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: false,
        videoWidth: 390,
        videoHeight: 844,
        viewWidth: 390,
        viewHeight: 844,
        fullscreenSurface: true,
      ),
      isFalse,
    );
  });

  test('immersive Reels may attach after UI is ready', () {
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: true,
        videoWidth: 390,
        videoHeight: 844,
        viewWidth: 390,
        viewHeight: 844,
        fullscreenSurface: true,
      ),
      isTrue,
    );
  });

  test('typical 9:16 feed card must not cover the launch canvas', () {
    // FeedVideoPlayer clamps height to ~56% of the viewport.
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: true,
        videoWidth: 390,
        videoHeight: 473,
        viewWidth: 390,
        viewHeight: 844,
      ),
      isFalse,
    );
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: true,
        videoWidth: 160,
        videoHeight: 90,
        viewWidth: 390,
        viewHeight: 844,
      ),
      isTrue,
    );
  });

  test('invalid sizes never attach a DOM video', () {
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: true,
        videoWidth: 0,
        videoHeight: 200,
        viewWidth: 390,
        viewHeight: 844,
      ),
      isFalse,
    );
    expect(
      DomVideoTouchPolicy.allowDomVideoAttach(
        uiReady: true,
        videoWidth: double.infinity,
        videoHeight: double.infinity,
        viewWidth: 390,
        viewHeight: 844,
        fullscreenSurface: true,
      ),
      isFalse,
    );
  });
}
