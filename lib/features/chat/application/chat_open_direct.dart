import 'dart:async';

import '../../../models/chat_models.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import 'chat_thread_prefetch.dart';

/// Open a DM instantly when the hub cache already has that peer.
class ChatOpenDirect {
  ChatOpenDirect._();

  static final Map<int, Future<ChatConversation>> _inflight = {};

  static int stubIdForPeer(int userId) => userId > 0 ? -userId : 0;

  static bool isStubId(int conversationId) => conversationId <= 0;

  static ChatConversation stubForPeer(ChatUserBrief peer) {
    return ChatConversation(
      id: stubIdForPeer(peer.id),
      type: 'direct',
      peer: peer,
      updatedAt: DateTime.now(),
    );
  }

  static ChatConversation? peekOrStub(
    int userId, {
    ChatUserBrief? peer,
  }) {
    final cached = peek(userId);
    if (cached != null) return cached;
    if (peer != null && peer.id == userId && userId > 0) {
      return stubForPeer(peer);
    }
    return null;
  }

  /// Cache or a local stub so the thread can paint before POST /chats/direct.
  static Future<ChatConversation> openNow(
    int userId, {
    ChatUserBrief? peer,
  }) async {
    final cached = peek(userId);
    if (cached != null) {
      if (cached.id > 0) {
        unawaited(ChatThreadPrefetch.warm(cached.id));
      }
      unawaited(_refresh(userId));
      return cached;
    }
    return resolveAndWarm(userId);
  }

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

  static ChatConversation? peekSavedAmong(Iterable<ChatConversation> chats) {
    for (final chat in chats) {
      if (chat.isSaved) return chat;
    }
    return null;
  }

  static Future<List<ChatConversation>> listForPicker() async {
    final cached = await ChatCacheService.conversationsForPicker();
    if (cached.isNotEmpty) return cached;
    final fresh = await ChatService.listConversations();
    if (fresh.isNotEmpty) {
      await ChatCacheService.saveConversations(fresh);
    }
    return fresh;
  }

  static Future<ChatConversation> resolveAndWarm(int userId) async {
    final conv = await resolve(userId);
    unawaited(ChatThreadPrefetch.warm(conv.id));
    return conv;
  }

  static Future<ChatConversation> _refresh(int userId) {
    return _inflight.putIfAbsent(userId, () async {
      try {
        final conv = await ChatService.openDirectChat(userId);
        await ChatCacheService.upsertConversation(conv);
        return conv;
      } finally {
        _inflight.remove(userId);
      }
    });
  }
}
