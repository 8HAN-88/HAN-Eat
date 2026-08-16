import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/paid_features_service.dart';

void main() {
  test('UserStarGift parses listing and wear fields', () {
    final gift = UserStarGift.fromJson({
      'id': 8,
      'owner_id': 3,
      'stars': 50,
      'slug': 'crown',
      'title': 'Корона',
      'emoji': '👑',
      'status': 'kept',
      'is_collectible': true,
      'serial': 4,
      'listed_stars': 120,
      'is_worn': true,
      'seller_name': 'Ann',
      'seller_username': 'ann',
      'total_supply': 10,
    });
    expect(gift.isListed, isTrue);
    expect(gift.canSell, isTrue);
    expect(gift.canWear, isTrue);
    expect(gift.canTransfer, isFalse);
    expect(gift.isWorn, isTrue);
    expect(gift.sellerLabel, '@ann');
    expect(gift.serialLabel, '#4 / 10');
  });
}
