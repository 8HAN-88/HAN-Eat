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

  static String preview(String content, {required bool mine}) {
    final data = parse(content);
    final status = data?['status'] as String? ?? 'ended';
    final media = data?['media'] as String? ?? 'voice';
    final isVideo = media == 'video';
    final duration = data?['duration_sec'];
    final dur = duration is int
        ? duration
        : int.tryParse('$duration') ?? 0;

    switch (status) {
      case 'missed':
        return mine
            ? (isVideo ? '📹 Видеозвонок · без ответа' : '📞 Звонок · без ответа')
            : (isVideo ? '📹 Пропущенный видеозвонок' : '📞 Пропущенный звонок');
      case 'rejected':
        return isVideo ? '📹 Видеозвонок · отклонён' : '📞 Звонок · отклонён';
      case 'cancelled':
        return isVideo ? '📹 Видеозвонок · отменён' : '📞 Звонок · отменён';
      case 'ended':
        final mm = (dur ~/ 60).toString().padLeft(2, '0');
        final ss = (dur % 60).toString().padLeft(2, '0');
        final label = isVideo ? '📹 Видеозвонок' : '📞 Звонок';
        return dur > 0 ? '$label · $mm:$ss' : label;
      default:
        return isVideo ? '📹 Видеозвонок' : '📞 Звонок';
    }
  }
}
