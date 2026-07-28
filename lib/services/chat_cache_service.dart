import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';

/// Composer draft with optional in-progress reply target.
class ChatDraft {
  const ChatDraft({
    this.text = '',
    this.replyToMessageId,
    this.updatedAt,
  });

  final String text;
  final int? replyToMessageId;
  final DateTime? updatedAt;

  bool get isEmpty =>
      text.trim().isEmpty &&
      (replyToMessageId == null || replyToMessageId! <= 0);

  /// Hub preview body (without the red «Черновик:» prefix).
  String get hubPreview {
    final t = text.trim();
    if (t.isNotEmpty) return t;
    if (replyToMessageId != null && replyToMessageId! > 0) {
      return 'Ответ на сообщение';
    }
    return '';
  }

  bool get hasReply =>
      replyToMessageId != null && replyToMessageId! > 0;

  factory ChatDraft.fromJson(Map<String, dynamic> json) {
    final replyRaw = json['reply_to_message_id'];
    int? replyId;
    if (replyRaw is int) {
      replyId = replyRaw;
    } else if (replyRaw is String) {
      replyId = int.tryParse(replyRaw);
    }
    DateTime? updatedAt;
    final updatedRaw = json['updated_at'];
    if (updatedRaw is String) {
      updatedAt = DateTime.tryParse(updatedRaw);
    }
    return ChatDraft(
      text: json['text'] as String? ?? '',
      replyToMessageId: replyId != null && replyId > 0 ? replyId : null,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (replyToMessageId != null && replyToMessageId! > 0)
          'reply_to_message_id': replyToMessageId,
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  ChatDraft copyWith({
    String? text,
    int? replyToMessageId,
    DateTime? updatedAt,
    bool clearReply = false,
  }) {
    return ChatDraft(
      text: text ?? this.text,
      replyToMessageId:
          clearReply ? null : (replyToMessageId ?? this.replyToMessageId),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Локальный кэш чатов для мгновенного отображения при открытии.
class ChatCacheService {
  ChatCacheService._();

  static const _conversationsKey = 'chat_cache_conversations_v1';
  static const _threadPrefix = 'chat_cache_thread_v1_';
  static const _draftPrefix = 'chat_draft_v1_';
  static const _draftV2Prefix = 'chat_draft_v2_';
  static const _failedTextPrefix = 'chat_failed_text_v1_';

  static List<ChatConversation>? _memoryConversations;
  static final Map<int, ChatDraft> _memoryDrafts = {};

  static List<ChatConversation>? peekConversations() {
    final cached = _memoryConversations;
    if (cached == null || cached.isEmpty) return null;
    return List<ChatConversation>.from(cached);
  }

  /// Instant draft peek for hub list (Telegram "Черновик: …").
  static ChatDraft? peekDraft(int conversationId) {
    final draft = _memoryDrafts[conversationId];
    if (draft == null || draft.isEmpty) return null;
    return draft;
  }

  static Future<Map<int, ChatDraft>> loadDrafts(
    Iterable<int> conversationIds,
  ) async {
    final out = <int, ChatDraft>{};
    for (final id in conversationIds) {
      final draft = await loadDraft(id);
      if (draft != null && !draft.isEmpty) {
        out[id] = draft;
      }
    }
    return out;
  }

  static Future<void> warmUp() async {
    _memoryConversations = await _loadConversationsFromDisk();
  }

  static Future<List<ChatConversation>?> loadConversations() async {
    if (_memoryConversations != null && _memoryConversations!.isNotEmpty) {
      return List<ChatConversation>.from(_memoryConversations!);
    }
    final loaded = await _loadConversationsFromDisk();
    _memoryConversations = loaded;
    return loaded == null ? null : List<ChatConversation>.from(loaded);
  }

  static Future<List<ChatConversation>?> _loadConversationsFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_conversationsKey);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <ChatConversation>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        try {
          out.add(ChatConversation.fromJson(item));
        } catch (_) {}
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConversations(List<ChatConversation> items) async {
    if (items.isEmpty) return;
    _memoryConversations = List<ChatConversation>.from(items);
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        items.map(_conversationToJson).toList(growable: false),
      );
      await prefs.setString(_conversationsKey, encoded);
    } catch (_) {}
  }

  static Future<List<ChatMessage>?> loadThread(int conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_threadPrefix$conversationId');
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <ChatMessage>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        try {
          out.add(ChatMessage.fromJson(item));
        } catch (_) {}
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveThread(
    int conversationId,
    List<ChatMessage> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_threadPrefix$conversationId';
      if (messages.isEmpty) {
        await prefs.remove(key);
        return;
      }
      final slice = messages.length > 80
          ? messages.sublist(messages.length - 80)
          : messages;
      final encoded = jsonEncode(
        slice.map(_messageToJson).toList(growable: false),
      );
      await prefs.setString(key, encoded);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadFailedTextSends(
    int conversationId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_failedTextPrefix$conversationId');
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) item,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveFailedTextSends(
    int conversationId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_failedTextPrefix$conversationId';
      if (items.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(items));
      }
    } catch (_) {}
  }

  static Future<void> clearDraft(int conversationId) async {
    _memoryDrafts.remove(conversationId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_draftPrefix$conversationId');
      await prefs.remove('$_draftV2Prefix$conversationId');
    } catch (_) {}
  }

  static Future<ChatDraft?> loadDraft(int conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v2Raw = prefs.getString('$_draftV2Prefix$conversationId');
      if (v2Raw != null && v2Raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(v2Raw);
          if (decoded is Map<String, dynamic>) {
            final draft = ChatDraft.fromJson(decoded);
            if (draft.isEmpty || _isLikelyErrorDraft(draft.text.trim())) {
              await clearDraft(conversationId);
              return null;
            }
            _memoryDrafts[conversationId] = draft;
            return draft;
          }
        } catch (_) {}
      }
      final text = prefs.getString('$_draftPrefix$conversationId');
      if (text == null || text.trim().isEmpty) {
        _memoryDrafts.remove(conversationId);
        return null;
      }
      final trimmed = text.trim();
      if (_isLikelyErrorDraft(trimmed)) {
        await clearDraft(conversationId);
        return null;
      }
      final draft = ChatDraft(text: text);
      _memoryDrafts[conversationId] = draft;
      return draft;
    } catch (_) {
      return null;
    }
  }

  static bool _isLikelyErrorDraft(String text) {
    switch (text.toLowerCase()) {
      case 'network_error':
      case 'offline':
      case 'timeout':
        return true;
      default:
        return false;
    }
  }

  static Future<void> saveDraft(
    int conversationId,
    String text, {
    int? replyToMessageId,
    DateTime? updatedAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = ChatDraft(
        text: text,
        replyToMessageId: replyToMessageId,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );
      final v1Key = '$_draftPrefix$conversationId';
      final v2Key = '$_draftV2Prefix$conversationId';
      if (draft.isEmpty) {
        _memoryDrafts.remove(conversationId);
        await prefs.remove(v1Key);
        await prefs.remove(v2Key);
        return;
      }
      _memoryDrafts[conversationId] = draft;
      await prefs.setString(v2Key, jsonEncode(draft.toJson()));
      // Drop legacy plain-text draft once v2 is written.
      await prefs.remove(v1Key);
    } catch (_) {}
  }

  static Map<String, dynamic> _conversationToJson(ChatConversation c) {
    return {
      'id': c.id,
      'type': c.type,
      if (c.peer != null)
        'peer': {
          'id': c.peer!.id,
          'name': c.peer!.name,
          'username': c.peer!.username,
          'avatar_url': c.peer!.avatarUrl,
          if (c.peer!.lastSeenAt != null)
            'last_seen_at': c.peer!.lastSeenAt!.toUtc().toIso8601String(),
        },
      'title': c.title,
      'member_count': c.memberCount,
      'members_preview': c.membersPreview
          .map(
            (u) => {
              'id': u.id,
              'name': u.name,
              'username': u.username,
              'avatar_url': u.avatarUrl,
            },
          )
          .toList(),
      if (c.lastMessage != null) ...{
        'last_message': _messageToJson(c.lastMessage!),
      },
      'unread_count': c.unreadCount,
      'updated_at': c.updatedAt.toUtc().toIso8601String(),
      'pinned': c.pinned,
      'archived': c.archived,
      'muted': c.muted,
      if (c.createdByUserId != null) 'created_by_user_id': c.createdByUserId,
    };
  }

  static Map<String, dynamic> _messageToJson(ChatMessage m) {
    return {
      'id': m.id,
      'conversation_id': m.conversationId,
      'sender_id': m.senderId,
      'sender_name': m.senderName,
      'type': m.type,
      'content': m.content,
      'media_url': m.mediaUrl,
      'reply_to_message_id': m.replyToMessageId,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      if (m.editedAt != null)
        'edited_at': m.editedAt!.toUtc().toIso8601String(),
      'is_mine': m.isMine,
      'is_delivered': m.isDelivered,
      'is_read': m.isRead,
      'read_count': m.readCount,
      'disable_webpage_preview': m.disableWebpagePreview,
      'reactions': m.reactions
          .map(
            (r) => {
              'emoji': r.emoji,
              'count': r.count,
              'reacted_by_me': r.reactedByMe,
            },
          )
          .toList(),
    };
  }
}
