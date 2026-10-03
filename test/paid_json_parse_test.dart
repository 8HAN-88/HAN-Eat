import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/flex_subscription_service.dart';
import 'package:han_eat/services/paid_features_service.dart';
import 'package:han_eat/services/subscription_service.dart';

void main() {
  test('StarsBalance accepts web-style nums', () {
    final balance = StarsBalance.fromJson({
      'balance': 120.0,
      'creator_available_stars': 40.0,
      'creator_pending_stars': '8',
    });
    expect(balance.balance, 120);
    expect(balance.creatorAvailableStars, 40);
    expect(balance.creatorPendingStars, 8);
  });

  test('StarGift and UserStarGift accept web-style nums', () {
    final gift = StarGift.fromJson({
      'id': 3.0,
      'slug': 'crown',
      'title': 'Корона',
      'emoji': '👑',
      'stars': 50.0,
      'is_limited': true,
      'total_supply': 10.0,
      'sold_count': 2.0,
      'remaining': 8.0,
      'upgrade_stars': 25.0,
      'transfer_stars': 15.0,
    });
    expect(gift.id, 3);
    expect(gift.stars, 50);
    expect(gift.remaining, 8);
    expect(gift.isSoldOut, isFalse);

    final held = UserStarGift.fromJson({
      'id': 8.0,
      'owner_id': 3.0,
      'stars': 50.0,
      'slug': 'crown',
      'title': 'Корона',
      'emoji': '👑',
      'status': 'kept',
      'is_collectible': true,
      'serial': 4.0,
      'listed_stars': 120.0,
      'is_worn': true,
      'total_supply': 10.0,
      'display_order': 2.0,
    });
    expect(held.id, 8);
    expect(held.listedStars, 120);
    expect(held.serial, 4);
    expect(held.isListed, isTrue);
  });

  test('StarInvoice and giveaway accept web-style nums', () {
    final invoice = StarInvoice.fromJson({
      'id': 9.0,
      'bot_id': 2.0,
      'creator_user_id': 1.0,
      'title': 'Счёт',
      'amount_stars': 75.0,
      'status': 'pending',
    });
    expect(invoice.id, 9);
    expect(invoice.amountStars, 75);
    expect(invoice.isPayable, isTrue);

    final giveaway = StarGiveaway.fromJson({
      'id': 4.0,
      'channel_id': 11.0,
      'creator_user_id': 1.0,
      'prize_stars': 200.0,
      'winners_count': 3.0,
      'total_escrow_stars': 600.0,
      'status': 'active',
      'ends_at': DateTime.now().toUtc().toIso8601String(),
      'participants_count': 12.0,
      'premium_months': 1.0,
    });
    expect(giveaway.id, 4);
    expect(giveaway.prizeStars, 200);
    expect(giveaway.isActive, isTrue);
  });

  test('FlexMe accepts web-style nums and loose feature maps', () {
    final me = FlexMe.fromJson({
      'current_level': 18.0,
      'price_rub': 209.0,
      'max_level': 79.0,
      'active': true,
      'next_level': 19.0,
      'next_price_rub': 219.0,
      'levels': [
        <dynamic, dynamic>{
          'id': 1.0,
          'slug': 'ad_free',
          'title': 'Без рекламы',
          'assigned_level': 1.0,
          'min_level': 1.0,
          'max_level': 1.0,
          'unlocked': true,
        },
      ],
      'blocks': [
        <dynamic, dynamic>{
          'key': 'A',
          'title': 'Базовые',
          'min_level': 1.0,
          'max_level': 6.0,
        },
      ],
    });
    expect(me.currentLevel, 18);
    expect(me.priceRub, 209);
    expect(me.nextLevel, 19);
    expect(me.levels.single.slug, 'ad_free');
    expect(me.levels.single.assignedLevel, 1);
    expect(me.blocks.single.maxLevel, 6);
    expect(me.canCheckout, isTrue);
  });

  test('subscription status reads loose entitlement maps', () {
    final status = SubscriptionStatusResponse.fromJson({
      'is_plus': true,
      'is_active': true,
      'subscription_type': 'flex',
      'entitlements': <dynamic, dynamic>{
        'ad_free': true,
        'gif_search': true,
        'exclusive_reactions': true,
      },
      'upgrade_options': [
        <dynamic, dynamic>{
          'product': 'pro',
          'name': 'Pro',
          'monthly_price': 199.0,
          'remaining_days': 12.0,
        },
      ],
    });
    expect(status.hasAdFree, isTrue);
    expect(status.hasGifSearch, isTrue);
    expect(status.hasEntitlement('exclusive_reactions'), isTrue);
    expect(status.hasAnyPaid, isTrue);
    expect(status.upgradeOptions.single.remainingDays, 12);
    expect(status.upgradeOptions.single.monthlyPrice, 199);
  });
}
