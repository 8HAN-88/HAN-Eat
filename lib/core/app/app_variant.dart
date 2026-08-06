/// Product branding for the HanWe messenger build.
enum AppVariant {
  social;

  static AppVariant get current => AppVariant.social;

  bool get isSocial => true;

  String get appTitle => 'HanWe';
  String get shortAppTitle => 'HanWe';
  String get appDescription => 'Чаты, лента, каналы и общение';
}
