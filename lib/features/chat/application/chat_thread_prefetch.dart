import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';

/// Warm the thread cache while the chat route is opening (Telegram-like).
class ChatThreadPrefetch {
  ChatThreadPrefetch._();

  static final Set<int> _inFlight = <int>{};

  static Future<void> warm(int conversationId) async {
    if (conversationId <= 0) return;
    if (!_inFlight.add(conversationId)) return;
    try {
      final result = await ChatService.listMessages(
        conversationId: conversationId,
      );
      await ChatCacheService.saveThread(conversationId, result.items);
    } catch (_) {
    } finally {
      _inFlight.remove(conversationId);
    }
  }
}
