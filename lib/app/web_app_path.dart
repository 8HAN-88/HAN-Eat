/// PWA отдаётся с `/app/`. Это HTML-шелл, а не маршрут GoRouter.
bool isWebAppShellPath(String path) {
  var p = path.trim();
  if (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p == '/app' || p == '/app/index.html';
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
