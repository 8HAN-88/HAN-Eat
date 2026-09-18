import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/revenue_share_service.dart';

void main() {
  test('snapshot parses payout fields and last payout', () {
    final snap = RevenueShareSnapshot.fromJson({
      'referral_code': 'ABC12XYZ',
      'share_url': 'https://haneat.app/invite?ref=ABC12XYZ',
      'extra_ads_enabled': false,
      'referred_count': 2,
      'pending_kopecks': 100,
      'available_kopecks': 56000,
      'payout_hold_kopecks': 50000,
      'paid_kopecks': 1680,
      'as_viewer_kopecks': 70,
      'as_referrer_kopecks': 1750,
      'kopecks_per_star': 80,
      'min_card_kopecks': 50000,
      'convertible_stars': 700,
      'payouts': [
        {
          'id': 4,
          'user_id': 1,
          'kind': 'card',
          'amount_kopecks': 50000,
          'amount_stars': 0,
          'status': 'pending',
          'phone': '+79001234567',
          'recipient_name': 'Иван',
        },
      ],
      'last_payout': {
        'id': 3,
        'user_id': 1,
        'kind': 'stars',
        'amount_kopecks': 1680,
        'amount_stars': 21,
        'status': 'paid',
      },
    });
    expect(snap.availableRub, '560.00 ₽');
    expect(snap.payoutHoldRub, '500.00 ₽');
    expect(snap.canRequestCard, isTrue);
    expect(snap.canConvertStars, isTrue);
    expect(snap.payouts.single.kindLabel, 'На карту / СБП');
    expect(snap.payouts.single.statusLabel, 'В обработке');
    expect(snap.lastPayout?.amountStars, 21);
    expect(snap.lastPayout?.kindLabel, 'Обменять на звёзды');
  });
}
