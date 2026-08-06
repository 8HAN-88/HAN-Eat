/// Product branding for the HanWe messenger build.
///
/// Kitchen / HAN Eat was removed; this type remains so existing call sites
/// (`AppVariant.current.appTitle`, etc.) keep working.
enum AppVariant {
  social;

  static AppVariant get current => AppVariant.social;

  bool get isSocial => true;
  bool get isKitchen => false;

  String get appTitle => 'HanWe';
  String get shortAppTitle => 'HanWe';
  String get appDescription => 'Чаты, лента, каналы и общение';
}
