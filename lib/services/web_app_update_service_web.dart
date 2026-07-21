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

  // Do not wipe Cache Storage here — on iPhone Safari that stalls the tab
  // into a white screen / "server stopped responding" during reload.

  final cb = DateTime.now().millisecondsSinceEpoch.toString();
  final v = (build != null && build.isNotEmpty) ? build : cb;
  // assign (not replace): Safari iOS often hangs on location.replace at boot.
  html.window.location.assign('/app/?v=$v&go=1&_cb=$cb');
}
