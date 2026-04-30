// Утилита для оптимизации URL изображений
// Помогает использовать обработанные (resized) версии изображений, как в Telegram

/// Получить оптимизированный URL изображения (medium версия если доступна)
/// Это помогает избежать размытия изображений при отображении
String getOptimizedImageUrl(String originalUrl) {
  // Если URL уже содержит _medium, используем его
  if (originalUrl.contains('_medium.')) {
    return originalUrl;
  }
  
  // Пытаемся получить medium версию, заменяя расширение на _medium.jpg
  // Например: uploads/user_1/2025/01/15/uuid.jpg -> uploads/user_1/2025/01/15/uuid_medium.jpg
  try {
    final uri = Uri.parse(originalUrl);
    final path = uri.path;
    
    // Если это локальный URL или URL из uploads, пытаемся получить medium версию
    if (path.contains('/uploads/') || originalUrl.contains('localhost')) {
      // Заменяем расширение на _medium.jpg
      final mediumPath = path.replaceAllMapped(
        RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false),
        (match) => '_medium.jpg',
      );
      
      // Если путь изменился, создаем новый URL
      if (mediumPath != path) {
        final newUri = uri.replace(path: mediumPath);
        return newUri.toString();
      }
    }
  } catch (e) {
    // Если не удалось распарсить URL, возвращаем оригинал
    // ignore: avoid_print
    print('Error optimizing image URL: $e');
  }
  
  // Возвращаем оригинальный URL если не удалось оптимизировать
  return originalUrl;
}

