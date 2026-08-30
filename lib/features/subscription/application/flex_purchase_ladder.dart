/// Одна платная подписка: цена уровня и куда вести со старых тарифов.
class FlexPurchaseLadder {
  const FlexPurchaseLadder._();

  static const int basePriceRub = 39;
  static const int stepPriceRub = 10;
  static const int minLevel = 1;
  static const int maxLevel = 79;

  static int priceRub(int level) {
    final clamped = level.clamp(minLevel, maxLevel);
    return basePriceRub + (clamped - 1) * stepPriceRub;
  }

  /// Старые AI / Creator / Pro открывают полный набор того тарифа.
  static int levelForClassicProduct(String? product) {
    switch (product) {
      case 'ai':
        return 9;
      case 'creator':
        return 16;
      case 'pro':
        return 18;
      default:
        return 0;
    }
  }

  /// Обратная метка на лестнице: какой классический пакет закрывает уровень.
  static String? classicProductAtLevel(int level) {
    switch (level) {
      case 9:
        return 'ai';
      case 16:
        return 'creator';
      case 18:
        return 'pro';
      default:
        return null;
    }
  }
}
