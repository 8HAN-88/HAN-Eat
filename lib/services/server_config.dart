import 'dart:io' if (dart.library.html) 'dart:html';
import 'package:flutter/foundation.dart';

import '../core/config/app_build_config.dart';

/// Базовый URL backend API.
///
/// Dev по умолчанию: https://api.haneat.app (Timeweb).
/// Локальный backend: `--dart-define=HANEAT_API_BASE=http://127.0.0.1:5001`
class ServerConfig {
  static String get _configuredRoot => AppBuildConfig.apiBaseRoot;

  /// `localhost` часто резолвится в `::1` (IPv6), а uvicorn может слушать только IPv4 —
  /// клиент получает отказ соединения. Явно используем IPv4 loopback.
  static String _ipv4Loopback(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host == 'localhost') {
        return uri.replace(host: '127.0.0.1').toString();
      }
    } catch (_) {}
    return url;
  }

  /// Получить базовый URL сервера в зависимости от платформы
  static String get baseUrl {
    final root = _ipv4Loopback(_configuredRoot);

    // В браузере совмещаем хост со страницей (localhost vs 127.0.0.1), иначе часть проверок/CORS ведёт себя неожиданно.
    if (kIsWeb) {
      try {
        final page = Uri.base;
        if (page.scheme != 'file' &&
            page.host.isNotEmpty &&
            (page.host == 'localhost' || page.host == '127.0.0.1')) {
          final apiUri = Uri.parse(root);
          final port = apiUri.hasPort ? apiUri.port : 5001;
          final scheme = page.scheme == 'https' ? 'https' : 'http';
          return Uri(scheme: scheme, host: page.host, port: port).toString();
        }
      } catch (_) {}
      return root;
    }

    try {
      final platform = (Platform as dynamic).operatingSystem as String;
      if (platform == 'android') {
        final uri = Uri.parse(root);
        if (uri.host == '127.0.0.1') {
          return uri.replace(host: '10.0.2.2').toString();
        }
        return root;
      }
      return root;
    } catch (_) {
      return root;
    }
  }

  /// Получить базовый URL API (с /api/v1)
  static String get apiBaseUrl => '$baseUrl/api/v1';

  /// Подставить доступный хост для медиа-URL (для эмулятора: localhost → 10.0.2.2).
  /// Относительные пути (начинающиеся с /) дополняются baseUrl.
  static String resolveMediaUrl(String url) {
    if (url.isEmpty) return url;
    // Относительный путь с бэкенда (например /media/recipes/xxx.jpg)
    if (url.startsWith('/')) {
      final base = baseUrl.endsWith('/') ? baseUrl : baseUrl;
      return '$base$url';
    }
    // Путь без схемы: media/… или uploads/…
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('data:') &&
        !url.startsWith('file:')) {
      final base = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      return '$base/$url';
    }
    try {
      final uri = Uri.parse(url);
      if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
        final resolved = Uri.parse(baseUrl).replace(
          path: uri.path,
          query: uri.query,
          fragment: uri.fragment,
        );
        return resolved.toString();
      }
    } catch (_) {}
    return url;
  }

  static String _recipeImageProxyUrl(String originalUrl) =>
      '$apiBaseUrl/recipe-image-proxy?url=${Uri.encodeComponent(originalUrl)}';

  static bool _isSpoonacularImageUrl(String url) =>
      url.startsWith('https://img.spoonacular.com') ||
      url.startsWith('https://spoonacular.com');

  /// URL для отображения фото рецепта.
  /// Spoonacular напрямую из РФ часто «висит» десятки секунд — на production идём через API (Amsterdam).
  static String resolveRecipeImageUrl(String url) {
    if (url.isEmpty) return url;
    if (_isSpoonacularImageUrl(url)) {
      final root = _configuredRoot.toLowerCase();
      final isLocalDev = root.contains('127.0.0.1') ||
          root.contains('localhost') ||
          root.contains('10.0.2.2');
      if (!isLocalDev || kIsWeb) {
        return _recipeImageProxyUrl(url);
      }
      return url;
    }
    return resolveMediaUrl(url);
  }

  /// Аватар канала/автора в карточке: локальные URL как есть; внешние HTTPS на iOS/Android — через image-proxy.
  static String resolvePublisherAvatarUrl(String url) {
    if (url.isEmpty) return url;
    final resolved = resolveRecipeImageUrl(resolveMediaUrl(url));
    if (kIsWeb) return resolved;
    try {
      final imageUri = Uri.parse(resolved);
      if (imageUri.scheme != 'https') return resolved;
      final apiHost = Uri.parse(baseUrl).host;
      if (imageUri.host.toLowerCase() == apiHost.toLowerCase()) {
        return resolved;
      }
      return _recipeImageProxyUrl(resolved);
    } catch (_) {
      return resolved;
    }
  }
}
