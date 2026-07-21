import 'dart:html' as html;

String _reloadGuardKey(String? build) =>
    'haneat_web_update_reload_${build ?? 'unknown'}';

/// Перезагрузка на свежий app shell. Один раз на билд за вкладку
/// (sessionStorage), чтобы не зациклить Safari.
Future<void> reloadWebPage({String? build}) async {
  try {
    final guardKey = _reloadGuardKey(build);
    if (html.window.sessionStorage[guardKey] == '1') {
      return;
    }
    html.window.sessionStorage[guardKey] = '1';
  } catch (_) {}

  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final reg in regs) {
        await reg.unregister();
      }
    }
  } catch (_) {}

  try {
    final keys = await html.window.caches?.keys();
    if (keys != null) {
      for (final key in keys) {
        await html.window.caches?.delete(key);
      }
    }
  } catch (_) {}

  final cb = DateTime.now().millisecondsSinceEpoch.toString();
  final v = (build != null && build.isNotEmpty) ? build : cb;
  // go=1 is required on iPhone: /app/ without it only shows the continue gate
  // and never starts Flutter (users see a stuck dark screen).
  html.window.location.replace('/app/?v=$v&go=1&_cb=$cb');
}
