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

  /// Старые AI / Creator / Pro открывают полный набор того тарифа, не первый
  /// уровень границы: AI = вся зона B, Creator = авторские до Pro, Pro = 10.
  static int levelForClassicProduct(String? product) {
    switch (product) {
      case 'ai':
        return 6;
      case 'creator':
        return 9;
      case 'pro':
        return 10;
      default:
        return 0;
    }
  }

  /// Обратная метка на лестнице: какой классический пакет закрывает уровень.
  static String? classicProductAtLevel(int level) {
    switch (level) {
      case 6:
        return 'ai';
      case 9:
        return 'creator';
      case 10:
        return 'pro';
      default:
        return null;
    }
  }
}
