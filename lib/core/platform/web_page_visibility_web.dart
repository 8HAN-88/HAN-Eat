import 'dart:html' as html;

/// При смене видимости вкладки PWA — пауза/возобновление фоновых соединений.
void registerWebPageVisibilityListener(
  void Function() onVisible, {
  void Function()? onHidden,
}) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    } else if (onHidden != null) {
      onHidden();
    }
  });
}
