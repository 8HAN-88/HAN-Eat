// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void syncWebDocumentTheme({required bool isDark, bool midnight = false}) {
  try {
    final root = html.document.documentElement;
    if (root != null) {
      root.classes.toggle('hanwe-theme-light', !isDark);
      root.classes.toggle('hanwe-theme-dark', isDark);
      root.classes.toggle('hanwe-theme-midnight', midnight && isDark);
    }
    final bg = !isDark
        ? '#F4F4F5'
        : midnight
            ? '#000000'
            : '#0F1319';
    final text = isDark ? '#F7F8FA' : '#121821';
    final card = !isDark
        ? '#FFFFFF'
        : midnight
            ? '#0A0A0A'
            : '#1A212B';
    final field = !isDark
        ? '#F1F3F5'
        : midnight
            ? '#111111'
            : '#121821';
    root?.style.setProperty('--bg', bg);
    root?.style.setProperty('--text', text);
    root?.style.setProperty('--card', card);
    root?.style.setProperty('--field', field);
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
