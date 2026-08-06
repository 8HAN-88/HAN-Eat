/// Заголовок поста для UI (в т.ч. legacy body-поля старых публикаций).
library;

import '../models/post_model.dart';

bool isMeaningfulPostTitle(String? value) {
  final s = value?.trim() ?? '';
  if (s.isEmpty || s == '.' || s == '…' || s == '...') return false;
  // Старые автогенерированные заглушки.
  final lower = s.toLowerCase();
  if (lower == 'recipe' || lower == 'пост' || lower == 'post') return false;
  return true;
}

String? resolvePostDisplayTitle({
  String? title,
  Map<String, dynamic>? body,
}) {
  final candidates = <String?>[
    title?.trim(),
    body?['title']?.toString().trim(),
    body?['translated_title']?.toString().trim(),
    body?['name']?.toString().trim(),
  ];
  final nested = body?['recipe'];
  if (nested is Map<String, dynamic>) {
    candidates.add(nested['title']?.toString().trim());
  }
  for (final c in candidates) {
    if (isMeaningfulPostTitle(c)) return c;
  }
  return null;
}

String displayTitleForPost(PostModel post, {String fallback = 'Пост'}) {
  return resolvePostDisplayTitle(title: post.title, body: post.body) ??
      fallback;
}

String? extractLegacyBodyImageUrl(Map<String, dynamic>? body) {
  if (body == null) return null;
  for (final key in ['image', 'source_image']) {
    final v = body[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  final nested = body['recipe'];
  if (nested is Map<String, dynamic>) {
    for (final key in ['image', 'source_image']) {
      final v = nested[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  return null;
}
