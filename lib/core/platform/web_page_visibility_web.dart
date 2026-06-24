import 'dart:html' as html;

/// При смене видимости вкладки PWA — пауза/возобновление фоновых соединений.
void registerWebPageVisibilityListener(
  void Function() onVisible, {
  void Function()? onHidden,
}) {
  void handleVisible() {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  }

  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    } else if (onHidden != null) {
      onHidden();
    }
  });

  // Safari: возврат из bfcache / другой вкладки.
  html.window.onPageShow.listen((_) => handleVisible());
  html.window.onFocus.listen((_) => handleVisible());
}
