import 'dart:convert';

/// Labels for chat `type=call` service bubbles (Telegram-like).
class CallMessageLabels {
  CallMessageLabels._();

  static Map<String, dynamic>? parse(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String mediaOf(String content) {
    final data = parse(content);
    return (data?['media'] as String?)?.trim().isNotEmpty == true
        ? (data!['media'] as String).trim()
        : 'voice';
  }

  static bool isGroupOf(String content) {
    final data = parse(content);
    final kind = (data?['kind'] ?? data?['call_kind'] ?? 'direct').toString();
    return kind == 'group';
  }

  static String preview(String content, {required bool mine}) {
    final data = parse(content);
    final status = data?['status'] as String? ?? 'ended';
    final media = data?['media'] as String? ?? 'voice';
    final isVideo = media == 'video';
    final isGroup = isGroupOf(content);
    final duration = data?['duration_sec'];
    final dur = duration is int
        ? duration
        : int.tryParse('$duration') ?? 0;

    final base = isGroup
        ? (isVideo ? '📹 Групповой видеозвонок' : '📞 Групповой звонок')
        : (isVideo ? '📹 Видеозвонок' : '📞 Звонок');

    switch (status) {
      case 'missed':
        if (mine) {
          return '$base · без ответа';
        }
        return isGroup
            ? (isVideo
                ? '📹 Пропущенный групповой видеозвонок'
                : '📞 Пропущенный групповой звонок')
            : (isVideo ? '📹 Пропущенный видеозвонок' : '📞 Пропущенный звонок');
      case 'rejected':
        return '$base · отклонён';
      case 'cancelled':
        return '$base · отменён';
      case 'ended':
        final mm = (dur ~/ 60).toString().padLeft(2, '0');
        final ss = (dur % 60).toString().padLeft(2, '0');
        return dur > 0 ? '$base · $mm:$ss' : base;
      default:
        return base;
    }
  }
}
