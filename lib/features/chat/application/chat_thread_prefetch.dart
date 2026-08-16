import '../../../models/chat_models.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import 'chat_message_integrate.dart';

/// First page of a thread, kept briefly so open + `_load` share one fetch.
class ChatThreadPrefetchPage {
  const ChatThreadPrefetchPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.pinnedMessage,
    this.pinnedMessages = const [],
    required this.fetchedAt,
  });

  final List<ChatMessage> items;
  final bool hasMore;
  final int? nextCursor;
  final ChatMessage? pinnedMessage;
  final List<ChatMessage> pinnedMessages;
  final DateTime fetchedAt;

  bool isFresh([Duration maxAge = ChatThreadPrefetch.freshnessWindow]) {
    return DateTime.now().difference(fetchedAt) <= maxAge;
  }
}

/// Warm the thread cache while the chat route is opening (Telegram-like).
///
/// Hub tap and thread `_load` share the same in-flight [listMessages] so
/// opening a chat does not hit the API twice.
class ChatThreadPrefetch {
  ChatThreadPrefetch._();

  static const Duration freshnessWindow = Duration(seconds: 3);

  static final Map<int, Future<ChatThreadPrefetchPage?>> _inFlight = {};
  static final Map<int, ChatThreadPrefetchPage> _fresh = {};

  static Future<void> warm(int conversationId) async {
    await page(conversationId);
  }

  /// Same future for concurrent callers; reuses a page younger than 3s.
  static Future<ChatThreadPrefetchPage?> page(int conversationId) {
    if (conversationId <= 0) return Future<ChatThreadPrefetchPage?>.value(null);
    final existing = _inFlight[conversationId];
    if (existing != null) return existing;
    final cached = takeFresh(conversationId);
    if (cached != null) {
      return Future<ChatThreadPrefetchPage?>.value(cached);
    }
    final future = _fetch(conversationId).whenComplete(() {
      _inFlight.remove(conversationId);
    });
    _inFlight[conversationId] = future;
    return future;
  }

  static ChatThreadPrefetchPage? takeFresh(int conversationId) {
    final cached = _fresh[conversationId];
    if (cached == null || !cached.isFresh()) return null;
    return cached;
  }

  static Future<ChatThreadPrefetchPage?>? inFlight(int conversationId) {
    return _inFlight[conversationId];
  }

  static Future<ChatThreadPrefetchPage?> _fetch(int conversationId) async {
    try {
      final result = await ChatService.listMessages(
        conversationId: conversationId,
      );
      final fetched = ChatThreadPrefetchPage(
        items: result.items,
        hasMore: result.hasMore,
        nextCursor: result.nextCursor,
        pinnedMessage: result.pinnedMessage,
        pinnedMessages: result.pinnedMessages,
        fetchedAt: DateTime.now(),
      );
      _fresh[conversationId] = fetched;
      final previous = ChatCacheService.peekThread(conversationId) ?? const [];
      final keepTempIds = {
        for (final local in previous)
          if (local.id < 0) local.id,
      };
      final merged = keepTempIds.isEmpty
          ? result.items
          : preserveOptimisticOutgoing(
              previous: previous,
              serverItems: result.items,
              keepTempIds: keepTempIds,
              isDuplicate: _isDuplicateOutgoing,
            );
      await ChatCacheService.saveThread(conversationId, merged);
      return fetched;
    } catch (_) {
      return takeFresh(conversationId);
    }
  }

  static bool _isDuplicateOutgoing(ChatMessage local, ChatMessage incoming) {
    final ca = (local.clientMessageId ?? '').trim();
    final cb = (incoming.clientMessageId ?? '').trim();
    if (ca.isNotEmpty && cb.isNotEmpty) return ca == cb;
    return local.isMine &&
        incoming.isMine &&
        local.type == incoming.type &&
        local.content == incoming.content;
  }

  static void debugReset() {
    _inFlight.clear();
    _fresh.clear();
  }

  static void debugSeed(int conversationId, ChatThreadPrefetchPage page) {
    _fresh[conversationId] = page;
  }

  static void debugSetInFlight(
    int conversationId,
    Future<ChatThreadPrefetchPage?> future,
  ) {
    _inFlight[conversationId] = future;
  }
}
