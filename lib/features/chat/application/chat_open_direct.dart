import 'dart:async';

import '../../../models/chat_models.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import 'chat_thread_prefetch.dart';

/// Open a DM instantly when the hub cache already has that peer.
class ChatOpenDirect {
  ChatOpenDirect._();

  static ChatConversation? peekAmong(
    Iterable<ChatConversation> chats,
    int userId,
  ) {
    if (userId <= 0) return null;
    for (final chat in chats) {
      if (chat.isGroup || chat.isSaved) continue;
      if (chat.peer?.id == userId) return chat;
    }
    return null;
  }

  static ChatConversation? peek(int userId) {
    return ChatCacheService.peekDirectWithUser(userId) ??
        peekAmong(ChatCacheService.peekConversations() ?? const [], userId);
  }

  /// Cache-first: return the known DM immediately, refresh in the background.
  static Future<ChatConversation> resolve(int userId) async {
    final cached = peek(userId);
    if (cached != null) {
      unawaited(_refresh(userId));
      return cached;
    }
    return _refresh(userId);
  }

  static Future<ChatConversation> resolveAndWarm(int userId) async {
    final conv = await resolve(userId);
    unawaited(ChatThreadPrefetch.warm(conv.id));
    return conv;
  }

  static Future<ChatConversation> _refresh(int userId) async {
    final conv = await ChatService.openDirectChat(userId);
    await ChatCacheService.upsertConversation(conv);
    return conv;
  }
}
