import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/subscription/application/flex_entitlements.dart';
import 'package:han_eat/models/video_quality_preference.dart';
import 'package:han_eat/services/subscription_service.dart';

void main() {
  test('exclusive reactions appear only when unlocked', () {
    expect(flexChatQuickReactions(false), isNot(contains('💎')));
    expect(flexChatQuickReactions(true), contains('💎'));
    expect(flexPostReactions(false), isNot(contains('💎')));
    expect(flexPostReactions(true), contains('💎'));
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

  test('creator slugs are checked separately', () {
    final status = SubscriptionStatusResponse(
      isPlus: false,
      isActive: true,
      subscriptionType: 'free',
      entitlements: const {'creator_tools': true},
    );
    expect(status.canCreatorTools, isTrue);
    expect(status.canSchedulePosts, isFalse);
    expect(status.canPromotePosts, isFalse);
    expect(status.canOfflineSaved, isFalse);
  });

  test('catalog leftover slugs are queryable', () {
    final status = SubscriptionStatusResponse(
      isPlus: false,
      isActive: true,
      subscriptionType: 'flex',
      entitlements: const {
        'ad_free': true,
        'gif_search': true,
        'story_viewers': true,
        'chat_translation': true,
        'extra_pins': true,
        'silent_send': true,
        'live_location': true,
        'premium_stickers': true,
        'message_effects': true,
        'scheduled_messages': true,
        'privacy_plus': true,
        'larger_uploads': true,
        'premium_badge': true,
        'profile_decoration': true,
      },
    );
    expect(status.hasAdFree, isTrue);
    expect(status.hasGifSearch, isTrue);
    expect(status.hasStoryViewers, isTrue);
    expect(status.hasChatTranslation, isTrue);
    expect(status.hasExtraPins, isTrue);
    expect(status.hasSilentSend, isTrue);
    expect(status.hasLiveLocation, isTrue);
    expect(status.hasPremiumStickers, isTrue);
    expect(status.hasMessageEffects, isTrue);
    expect(status.hasScheduledMessages, isTrue);
    expect(status.hasPrivacyPlus, isTrue);
    expect(status.hasLargerUploads, isTrue);
    expect(status.hasPremiumBadge, isTrue);
    expect(status.hasProfileDecoration, isTrue);
    expect(status.hasEntitlement('business_hours'), isFalse);
  });
}
