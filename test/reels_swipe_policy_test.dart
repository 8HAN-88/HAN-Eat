import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/reels/application/reels_swipe_policy.dart';
import 'package:han_eat/widgets/cover_network_video.dart';

void main() {
  test('web preloads the next reel immediately', () {
    expect(
      ReelsSwipePolicy.neighborInitDelay(offsetFromCurrent: 1, isWeb: true),
      Duration.zero,
    );
    expect(
      ReelsSwipePolicy.neighborInitDelay(offsetFromCurrent: 1, isWeb: false),
      const Duration(milliseconds: 180),
    );
  });

  test('web skips mid-playback quality swap', () {
    expect(ReelsSwipePolicy.skipQualityUpgrade(isWeb: true), isTrue);
    expect(ReelsSwipePolicy.skipQualityUpgrade(isWeb: false), isFalse);
  });

  test('cover rebuilds only on layout or error, not every tick', () {
    expect(
      shouldRebuildCoverVideo(
        wasInitialized: true,
        isInitialized: true,
        oldWidth: 720,
        oldHeight: 1280,
        newWidth: 720,
        newHeight: 1280,
        hadError: false,
        hasError: false,
      ),
      isFalse,
    );
    expect(
      shouldRebuildCoverVideo(
        wasInitialized: false,
        isInitialized: true,
        oldWidth: 0,
        oldHeight: 0,
        newWidth: 720,
        newHeight: 1280,
        hadError: false,
        hasError: false,
      ),
      isTrue,
    );
  });
}
