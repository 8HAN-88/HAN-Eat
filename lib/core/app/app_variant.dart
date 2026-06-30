enum AppVariant {
  social,
  kitchen;

  static const _raw = String.fromEnvironment(
    'APP_VARIANT',
    defaultValue: 'social',
  );

  static AppVariant get current {
    switch (_raw.toLowerCase().trim()) {
      case 'kitchen':
        return AppVariant.kitchen;
      case 'social':
      default:
        return AppVariant.social;
    }
  }

  bool get isSocial => this == AppVariant.social;
  bool get isKitchen => this == AppVariant.kitchen;

  String get appTitle => isKitchen ? 'HAN Eat' : 'HanWe';
  String get shortAppTitle => isKitchen ? 'HAN Eat' : 'HanWe';
  String get appDescription => isKitchen
      ? 'Рецепты, меню и план питания'
      : 'Чаты, лента, каналы и общение';
}
