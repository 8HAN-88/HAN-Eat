import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/storage/hive_bootstrap.dart';

/// Persist pending/failed chat media so reload can retry like Telegram.
///
/// Uses Hive (IndexedDB on web). Skips items larger than [maxBytesPerItem].
class ChatMediaOutboxService {
  ChatMediaOutboxService._();

  static const boxName = 'chat_media_outbox_v1';
  static const maxBytesPerItem = 12 * 1024 * 1024; // 12 MB
  static const maxItemsPerConversation = 8;

  static Box? _box;

  static Future<Box?> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box;
    try {
      await ensureHiveReady();
      if (!Hive.isBoxOpen(boxName)) {
        _box = await Hive.openBox(boxName);
      } else {
        _box = Hive.box(boxName);
      }
      return _box;
    } catch (e) {
      debugPrint('ChatMediaOutbox open failed: $e');
      return null;
    }
  }

  static String _key(int conversationId, String clientMessageId) =>
      '${conversationId}_$clientMessageId';

  static Future<void> upsert({
    required int conversationId,
    required String clientMessageId,
    required int tempId,
    required String kind,
    required Uint8List bytes,
    String? fileName,
    int? replyToMessageId,
    int? voiceDurationSec,
    String? uploadedMediaUrl,
    int attempts = 0,
    int? lastRetryAfterSeconds,
    String? lastLimitedAtIso,
    String? createdAtIso,
    bool failed = true,
  }) async {
    if (bytes.isEmpty || bytes.length > maxBytesPerItem) return;
    final box = await _ensureBox();
    if (box == null) return;
    try {
      final key = _key(conversationId, clientMessageId);
      await box.put(key, {
        'conversation_id': conversationId,
        'client_message_id': clientMessageId,
        'temp_id': tempId,
        'kind': kind,
        'file_name': fileName,
        'reply_to_message_id': replyToMessageId,
        'voice_duration_sec': voiceDurationSec,
        'uploaded_media_url': uploadedMediaUrl,
        'attempts': attempts,
        'last_retry_after_seconds': lastRetryAfterSeconds,
        'last_limited_at': lastLimitedAtIso,
        'created_at': createdAtIso ?? DateTime.now().toUtc().toIso8601String(),
        'failed': failed,
        'bytes': bytes,
      });
      await _trimConversation(box, conversationId);
    } catch (e) {
      debugPrint('ChatMediaOutbox upsert failed: $e');
    }
  }

  static Future<void> remove({
    required int conversationId,
    required String clientMessageId,
  }) async {
    final box = await _ensureBox();
    if (box == null) return;
    try {
      await box.delete(_key(conversationId, clientMessageId));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadConversation(
    int conversationId,
  ) async {
    final box = await _ensureBox();
    if (box == null) return const [];
    final out = <Map<String, dynamic>>[];
    try {
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        if (map['conversation_id'] != conversationId) continue;
        final bytes = _asBytes(map['bytes']);
        if (bytes == null || bytes.isEmpty) continue;
        map['bytes'] = bytes;
        out.add(map);
      }
      out.sort((a, b) {
        final at = DateTime.tryParse('${a['created_at']}') ?? DateTime(0);
        final bt = DateTime.tryParse('${b['created_at']}') ?? DateTime(0);
        return at.compareTo(bt);
      });
    } catch (e) {
      debugPrint('ChatMediaOutbox load failed: $e');
    }
    return out;
  }

  static Uint8List? _asBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List) {
      try {
        return Uint8List.fromList(raw.cast<int>());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Future<void> _trimConversation(Box box, int conversationId) async {
    final keys = <dynamic>[];
    final created = <dynamic, DateTime>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['conversation_id'] != conversationId) continue;
      keys.add(key);
      created[key] =
          DateTime.tryParse('${raw['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (keys.length <= maxItemsPerConversation) return;
    keys.sort((a, b) => created[a]!.compareTo(created[b]!));
    final drop = keys.length - maxItemsPerConversation;
    for (var i = 0; i < drop; i++) {
      await box.delete(keys[i]);
    }
  }
}
