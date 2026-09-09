// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void notifyPrimaryUiReady() {
  try {
    html.window.dispatchEvent(html.CustomEvent('han-primary-ui-ready'));
  } catch (_) {}
  killLaunchOverlays();
}

void killLaunchOverlays() {
  try {
    html.document.getElementById('boot-splash')?.remove();
    for (final node in html.document.querySelectorAll(
      'video.hanwe-dom-reel, #hanwe-reel-touch',
    )) {
      node.remove();
    }
    final flutter = html.document.querySelector('flutter-view') ??
        html.document.querySelector('flt-glass-pane');
    if (flutter != null) {
      flutter.style
        ..setProperty('pointer-events', 'auto')
        ..setProperty('background-color', '#0F1319')
        ..setProperty('z-index', '2');
    }
  } catch (_) {}
}
