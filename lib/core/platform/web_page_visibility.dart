import 'web_page_visibility_stub.dart'
    if (dart.library.html) 'web_page_visibility_web.dart' as platform;

/// При возврате на вкладку браузера (PWA) — callback для прогрева API.
void registerWebPageVisibilityListener(void Function() onVisible) {
  platform.registerWebPageVisibilityListener(onVisible);
}
