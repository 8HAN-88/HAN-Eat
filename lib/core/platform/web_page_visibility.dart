import 'web_page_visibility_stub.dart'
    if (dart.library.html) 'web_page_visibility_web.dart' as platform;

/// Слушатель видимости вкладки браузера (PWA).
void registerWebPageVisibilityListener(
  void Function() onVisible, {
  void Function()? onHidden,
}) {
  platform.registerWebPageVisibilityListener(onVisible, onHidden: onHidden);
}
