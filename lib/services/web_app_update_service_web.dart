import 'dart:html' as html;

Future<void> reloadWebPage() async {
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

  final uri = Uri.parse(html.window.location.href);
  final build = uri.queryParameters['v'];
  if (build != null && build.isNotEmpty) {
    html.window.location.replace(uri.toString());
  } else {
    html.window.location.reload();
  }
}
