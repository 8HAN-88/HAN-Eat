import '../services/custom_emoji_registry.dart';

/// Normalize optional media caption for native save/share sheets.
String? normalizeMediaShareCaption(String? caption) {
  final trimmed = caption?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return previewTextWithCustomEmoji(trimmed);
}
