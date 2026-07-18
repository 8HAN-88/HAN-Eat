// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void notifyPrimaryUiReady() {
  try {
    html.window.dispatchEvent(html.CustomEvent('han-primary-ui-ready'));
  } catch (_) {}
}
