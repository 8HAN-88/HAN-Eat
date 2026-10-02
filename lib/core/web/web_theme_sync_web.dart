// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void syncWebDocumentTheme({required bool isDark}) {
  try {
    final root = html.document.documentElement;
    if (root != null) {
      root.classes.toggle('hanwe-theme-light', !isDark);
      root.classes.toggle('hanwe-theme-dark', isDark);
    }
    final bg = isDark ? '#0F1319' : '#F4F4F5';
    final text = isDark ? '#F7F8FA' : '#121821';
    root?.style.setProperty('--bg', bg);
    root?.style.setProperty('--text', text);
    html.document.body?.style.backgroundColor = bg;
    html.document.getElementById('app-underlay')?.style.backgroundColor = bg;
    final meta = html.document.querySelector('meta[name="theme-color"]');
    meta?.setAttribute('content', bg);
  } catch (_) {}
}

void setWebReelSeeThrough(bool enabled) {
  try {
    final root = html.document.documentElement;
    if (root == null) return;
    root.classes.toggle('hanwe-reel-see-through', enabled);
    root.classes.toggle('hanwe-reel-live', enabled);
  } catch (_) {}
}
