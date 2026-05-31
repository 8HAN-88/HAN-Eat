import 'package:flutter/foundation.dart';

import '../services/server_config.dart';

// Утилита для оптимизации URL изображений рецептов.

/// Превью Spoonacular: большие размеры (556x370) из РФ грузятся десятки секунд.
String shrinkSpoonacularImageUrl(
  String url, {
  String dimensions = '312x231',
}) {
  if (!url.contains('spoonacular.com')) return url;
  return url.replaceFirst(
    RegExp(r'-\d+x\d+(?=\.(jpg|jpeg|png|webp)$)', caseSensitive: false),
    '-$dimensions',
  );
}

/// URL для сетки карточек «Меню» (баланс скорости и чёткости на Retina).
String getRecipeCardImageUrl(String raw) =>
    getRecipeImageUrl(raw, spoonacularDimensions: '240x150');

/// URL для полноэкранного просмотра.
String getRecipeDetailImageUrl(String raw) =>
    getRecipeImageUrl(raw, spoonacularDimensions: '556x370');

/// Общая сборка URL изображения рецепта.
String getRecipeImageUrl(
  String raw, {
  String spoonacularDimensions = '312x231',
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  var url = trimmed;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }

  if (url.contains('img.spoonacular.com') || url.contains('spoonacular.com')) {
    return ServerConfig.resolveRecipeImageUrl(
      shrinkSpoonacularImageUrl(url, dimensions: spoonacularDimensions),
    );
  }

  return getOptimizedImageUrl(
    ServerConfig.resolveRecipeImageUrl(ServerConfig.resolveMediaUrl(trimmed)),
  );
}

/// Получить оптимизированный URL изображения (medium версия если доступна)
String getOptimizedImageUrl(String originalUrl) {
  if (originalUrl.contains('spoonacular.com')) {
    return originalUrl;
  }

  if (originalUrl.contains('_medium.')) {
    return originalUrl;
  }

  try {
    final uri = Uri.parse(originalUrl);
    final path = uri.path;
    final host = uri.host.toLowerCase();

    if (path.contains('/uploads/file/') ||
        path.contains('/api/v1/uploads/file/') ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1') {
      return originalUrl;
    }

    if (path.contains('/uploads/') || originalUrl.contains('localhost')) {
      final mediumPath = path.replaceAllMapped(
        RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false),
        (match) => '_medium.jpg',
      );

      if (mediumPath != path) {
        return uri.replace(path: mediumPath).toString();
      }
    }
  } catch (e) {
    debugPrint('Error optimizing image URL: $e');
  }

  return originalUrl;
}
