const _bootQueryKeys = {'go', 'v', '_cb', 'retry'};

String _normalizedPath(String path) {
  var p = path.trim();
  if (p.contains('?')) {
    p = p.split('?').first;
  }
  if (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// PWA отдаётся с `/app/`. Это HTML-шелл, а не маршрут GoRouter.
bool isWebAppShellPath(String path) {
  final p = _normalizedPath(path);
  return p == '/app' || p == '/app/index.html';
}

/// То, что видит GoRouter после `--base-href /app/`.
///
/// Браузер: `https://haneat.app/app/?go=1` → локация роутера `/` (не `/app`).
/// `/` не является маршрутом ленты (`/feed`) — без редиректа будет
/// «ошибка маршрута».
bool isGoRouterShellLocation(String path) {
  final p = _normalizedPath(path);
  return p.isEmpty || p == '/' || isWebAppShellPath(p);
}

/// Путь браузера → путь GoRouter.
///
/// `/app`, `/app/`, `/app/index.html` — корень шелла (null).
/// `/app/feed` → `/feed`. Обычные пути без `/app` не меняются.
/// `/` и пустая строка → null (открыть домашний экран).
String? browserPathToGoPath(String path) {
  var p = path.trim();
  if (p.isEmpty) return null;
  if (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (isWebAppShellPath(p)) return null;
  if (p.startsWith('/app/')) {
    p = p.substring('/app'.length);
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty || p == '/') return null;
  }
  if (p.isEmpty || p == '/') return null;
  return p;
}

/// Query для GoRouter: выкидываем служебные `go=1`, `v`, `_cb`, `retry`.
String? routerQueryFromUri(Uri uri) {
  final keep = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (_bootQueryKeys.contains(key)) return;
    keep[key] = value;
  });
  if (keep.isEmpty) return null;
  return Uri(queryParameters: keep).query;
}

/// One-shot: PWA открыли с HTML-шелла (`/app/?go=1` → `/`), не с сохранённого /feed.
class FeedShellLaunch {
  static bool skipReelsTab = false;

  static bool takeSkipReelsTab() {
    final value = skipReelsTab;
    skipReelsTab = false;
    return value;
  }
}
