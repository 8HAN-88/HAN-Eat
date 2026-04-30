import 'dart:io' if (dart.library.html) 'dart:html';
import 'package:flutter/foundation.dart';

/// Общий класс для определения правильного адреса сервера в зависимости от платформы
class ServerConfig {
  /// Получить базовый URL сервера в зависимости от платформы
  static String get baseUrl {
    if (kIsWeb) {
      // Для web используем localhost
      return 'http://localhost:5000';
    }
    
    // For native platforms only
    try {
      if (!kIsWeb) {
        final platform = (Platform as dynamic).operatingSystem as String;
        if (platform == 'android') {
          // Для Android эмулятора используем специальный адрес
          return 'http://10.0.2.2:5000';
        }
        // Для iOS и других платформ используем localhost
        return 'http://localhost:5000';
      }
    } catch (e) {
      // Platform checks may fail, use default
    }
    // Для других платформ (Windows, Linux, macOS) используем localhost
    return 'http://localhost:5000';
  }
  
  /// Получить базовый URL API (с /api/v1)
  static String get apiBaseUrl => '$baseUrl/api/v1';

  /// Подставить доступный хост для медиа-URL (для эмулятора: localhost → 10.0.2.2).
  /// Относительные пути (начинающиеся с /) дополняются baseUrl.
  static String resolveMediaUrl(String url) {
    if (url.isEmpty) return url;
    // Относительный путь с бэкенда (например /media/recipes/xxx.jpg)
    if (url.startsWith('/')) {
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl';
      return '$base$url';
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

  /// URL для отображения фото рецепта: Spoonacular — через прокси (обход CORS), остальные — resolveMediaUrl.
  static String resolveRecipeImageUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('https://img.spoonacular.com') || url.startsWith('https://spoonacular.com')) {
      return '$apiBaseUrl/recipes/image-proxy?url=${Uri.encodeComponent(url)}';
    }
    return resolveMediaUrl(url);
  }
}

