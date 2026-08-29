/// Одна платная подписка: цена уровня и куда вести со старых тарифов.
class FlexPurchaseLadder {
  const FlexPurchaseLadder._();

  static const int basePriceRub = 39;
  static const int stepPriceRub = 10;
  static const int minLevel = 1;
  static const int maxLevel = 10;

  static int priceRub(int level) {
    final clamped = level.clamp(minLevel, maxLevel);
    return basePriceRub + (clamped - 1) * stepPriceRub;
  }

  /// Старые AI / Creator / Pro открывают ту же ленту на нужной границе.
  static int levelForClassicProduct(String? product) {
    switch (product) {
      case 'ai':
        return 4;
      case 'creator':
        return 7;
      case 'pro':
        return 10;
      default:
        return 0;
    }
  }
}
