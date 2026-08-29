import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/subscription/application/flex_purchase_ladder.dart';

void main() {
  test('one ladder prices from 39 ₽', () {
    expect(FlexPurchaseLadder.priceRub(1), 39);
    expect(FlexPurchaseLadder.priceRub(2), 49);
    expect(FlexPurchaseLadder.priceRub(10), 129);
  });

  test('classic products land on the same ladder', () {
    expect(FlexPurchaseLadder.levelForClassicProduct('ai'), 6);
    expect(FlexPurchaseLadder.levelForClassicProduct('creator'), 9);
    expect(FlexPurchaseLadder.levelForClassicProduct('pro'), 10);
    expect(FlexPurchaseLadder.levelForClassicProduct(null), 0);
    expect(FlexPurchaseLadder.classicProductAtLevel(6), 'ai');
    expect(FlexPurchaseLadder.classicProductAtLevel(9), 'creator');
    expect(FlexPurchaseLadder.classicProductAtLevel(10), 'pro');
    expect(FlexPurchaseLadder.classicProductAtLevel(4), isNull);
  });
}
