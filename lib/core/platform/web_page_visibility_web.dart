import 'dart:html' as html;

/// При возврате на вкладку PWA — прогрев API и сессии.
void registerWebPageVisibilityListener(void Function() onVisible) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  });
}
