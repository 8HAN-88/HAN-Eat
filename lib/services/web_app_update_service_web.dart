import 'dart:html' as html;

Future<void> reloadWebPage({String? build}) async {
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
  final params = Map<String, String>.from(uri.queryParameters);
  if (build != null && build.isNotEmpty) {
    params['v'] = build;
  }
  params['_cb'] = DateTime.now().millisecondsSinceEpoch.toString();
  final next = uri.replace(queryParameters: params);
  html.window.location.replace(next.toString());
}
