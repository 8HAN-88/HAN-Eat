import 'package:flutter/foundation.dart';

import '../services/server_config.dart';

// Утилита для оптимизации URL изображений (включая legacy CDN).

/// Сжать oversized preview URL на legacy CDN (большие размеры грузятся медленно).
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

/// URL для сетки карточек (баланс скорости и чёткости на Retina).
String getRecipeCardImageUrl(String raw) =>
    getRecipeImageUrl(raw, spoonacularDimensions: '240x150');

/// URL для полноэкранного просмотра.
String getRecipeDetailImageUrl(String raw) =>
    getRecipeImageUrl(raw, spoonacularDimensions: '556x370');

/// Кандидаты URL для полноэкранного просмотра: оригинал, medium и fallback.
List<String> getFullscreenImageUrlCandidates(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  final isNetwork =
      trimmed.startsWith('http://') || trimmed.startsWith('https://');
  if (!isNetwork) return [trimmed];

  final resolved = ServerConfig.resolveMediaUrl(trimmed);
  final full = ServerConfig.resolvePublisherAvatarUrl(resolved);
  final medium =
      ServerConfig.resolvePublisherAvatarUrl(getOptimizedImageUrl(resolved));

  final candidates = <String>[];
  void add(String url) {
    if (url.isNotEmpty && !candidates.contains(url)) {
      candidates.add(url);
    }
  }

  add(full);
  if (medium != full) add(medium);

  if (trimmed.contains('spoonacular.com')) {
    for (final dim in ['556x370', '312x231', '240x150']) {
      add(getRecipeImageUrl(trimmed, spoonacularDimensions: dim));
    }
  }

  return candidates;
}

/// Общая сборка URL изображения (с proxy для legacy CDN при необходимости).
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
