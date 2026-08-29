import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/subscription/application/flex_entitlements.dart';
import 'package:han_eat/models/video_quality_preference.dart';
import 'package:han_eat/services/subscription_service.dart';

void main() {
  test('exclusive reactions appear only when unlocked', () {
    expect(flexChatQuickReactions(false), isNot(contains('💎')));
    expect(flexChatQuickReactions(true), contains('💎'));
  });

  test('priority reels bump auto to 1080p', () {
    expect(
      flexReelQuality(VideoQualityPreference.auto, priority: true),
      VideoQualityPreference.hd1080,
    );
    expect(
      flexReelQuality(VideoQualityPreference.dataSaver, priority: true),
      VideoQualityPreference.dataSaver,
    );
  });

  test('hasPro follows flex entitlements without classic tier', () {
    final status = SubscriptionStatusResponse(
      isPlus: false,
      isActive: true,
      subscriptionType: 'free',
      entitlements: const {'priority_support': true},
    );
    expect(status.hasPro, isTrue);
    expect(status.hasEntitlement('priority_support'), isTrue);
    expect(status.hasAnyPaid, isTrue);
  });
}
