// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

bool hardNavigateToRoute(String routePath, {bool addRecoverQuery = false}) {
  try {
    final current = Uri.base;
    final normalized = routePath.startsWith('/') ? routePath : '/$routePath';
    final query = <String, String>{...current.queryParameters};
    query.remove('recover');
    // GoRouter uses path-based URLs, not hash fragments.
    final next = Uri(
      scheme: current.scheme,
      host: current.host,
      port: current.hasPort ? current.port : null,
      path: normalized,
      queryParameters: <String, String>{
        ...query,
        if (addRecoverQuery)
          'recover': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    html.window.location.replace(next.toString());
    return true;
  } catch (_) {
    return false;
  }
}
