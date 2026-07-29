import 'dart:html' as html;

String _reloadGuardKey(String? build) =>
    'haneat_web_update_reload_${build ?? 'unknown'}';

/// Перезагрузка на свежий app shell.
///
/// Guard в sessionStorage хранит timestamp: повтор через 45s разрешён, если
/// прошлый assign не довёл до успешного boot (иначе Safari мог зациклиться).
Future<void> reloadWebPage({String? build}) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  try {
    final guardKey = _reloadGuardKey(build);
    final prevRaw = html.window.sessionStorage[guardKey];
    final prevMs = int.tryParse(prevRaw ?? '');
    if (prevMs != null && nowMs - prevMs < 45000) {
      return;
    }
    html.window.sessionStorage[guardKey] = '$nowMs';
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

  // Selective Cache API cleanup with a short timeout. Full Clear-Site-Data
  // (/fresh) can hang Safari; skipping wipe entirely leaves stale SW caches.
  try {
    await _wipeFlutterCaches().timeout(const Duration(milliseconds: 800));
  } catch (_) {}

  final cb = nowMs.toString();
  final v = (build != null && build.isNotEmpty) ? build : cb;
  // assign (not replace): Safari iOS often hangs on location.replace at boot.
  html.window.location.assign('/app/?v=$v&go=1&_cb=$cb');
}

Future<void> _wipeFlutterCaches() async {
  final caches = html.window.caches;
  if (caches == null) return;
  final keys = await caches.keys();
  for (final key in keys) {
    final name = key.toString().toLowerCase();
    if (name.contains('flutter') ||
        name.contains('main.dart') ||
        name.contains('haneat') ||
        name.contains('canvaskit')) {
      try {
        await caches.delete(key);
      } catch (_) {}
    }
  }
}
