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
    final live = html.document.documentElement?.classes.contains(
          'hanwe-reel-live',
        ) ??
        false;
    for (final node in html.document.querySelectorAll('#hanwe-reel-touch')) {
      node.remove();
    }
    if (live) return;
    for (final node in html.document.querySelectorAll('video.hanwe-dom-reel')) {
      node.remove();
    }
  } catch (_) {}
}
