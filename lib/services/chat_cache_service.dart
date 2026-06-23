import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';

/// Локальный кэш чатов для мгновенного отображения при открытии.
class ChatCacheService {
  ChatCacheService._();

  static const _conversationsKey = 'chat_cache_conversations_v1';
  static const _threadPrefix = 'chat_cache_thread_v1_';
  static const _draftPrefix = 'chat_draft_v1_';

  static List<ChatConversation>? _memoryConversations;

  static List<ChatConversation>? peekConversations() {
    final cached = _memoryConversations;
    if (cached == null || cached.isEmpty) return null;
    return List<ChatConversation>.from(cached);
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
    if (messages.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final slice = messages.length > 80
          ? messages.sublist(messages.length - 80)
          : messages;
      final encoded = jsonEncode(
        slice.map(_messageToJson).toList(growable: false),
      );
      await prefs.setString('$_threadPrefix$conversationId', encoded);
    } catch (_) {}
  }

  static Future<void> clearDraft(int conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_draftPrefix$conversationId');
    } catch (_) {}
  }

  static Future<String?> loadDraft(int conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString('$_draftPrefix$conversationId');
      if (text == null || text.trim().isEmpty) return null;
      final trimmed = text.trim();
      if (_isLikelyErrorDraft(trimmed)) {
        await prefs.remove('$_draftPrefix$conversationId');
        return null;
      }
      return text;
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

  static Future<void> saveDraft(int conversationId, String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = text.trim();
      final key = '$_draftPrefix$conversationId';
      if (trimmed.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, text);
      }
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
      'is_read': m.isRead,
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
