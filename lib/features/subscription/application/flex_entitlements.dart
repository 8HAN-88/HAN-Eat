import '../../../models/video_quality_preference.dart';

/// Эксклюзивные реакции, те же что на бэкенде.
const flexExclusiveReactions = ['💎', '👑', '⚡', '🦄', '✨', '🖤'];

List<String> flexChatQuickReactions(bool exclusive) => [
      '👍',
      '❤️',
      '😂',
      '😮',
      '😢',
      '🙏',
      if (exclusive) ...flexExclusiveReactions,
    ];

List<String> flexPostReactions(bool exclusive) => [
      '👍',
      '❤️',
      '😂',
      '🔥',
      '😮',
      '😢',
      if (exclusive) ...flexExclusiveReactions,
    ];

List<String> flexChatOverlayReactions(bool exclusive) => [
      '👍',
      '👌',
      '❤️',
      '🔥',
      '👎',
      '🥰',
      '👏',
      if (exclusive) ...flexExclusiveReactions.take(3),
    ];

VideoQualityPreference flexReelQuality(
  VideoQualityPreference pref, {
  required bool priority,
}) {
  if (!priority || pref == VideoQualityPreference.dataSaver) return pref;
  if (pref == VideoQualityPreference.auto) return VideoQualityPreference.hd1080;
  return pref;
}
