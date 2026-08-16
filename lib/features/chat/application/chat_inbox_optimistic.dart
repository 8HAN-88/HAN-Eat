import '../../../models/chat_models.dart';

/// Instant mute / pin / archive / unread patches for hub and thread.
class ChatInboxOptimistic {
  ChatInboxOptimistic._();

  static ChatConversation applyMute(
    ChatConversation chat, {
    required bool muted,
    DateTime? until,
    String? notifyMode,
  }) {
    return chat.copyWith(
      muted: muted,
      mutedUntil: until,
      clearMutedUntil: !muted || until == null,
      notifyMode: notifyMode ?? (muted ? 'mentions' : 'all'),
    );
  }

  static ChatConversation applyPin(
    ChatConversation chat, {
    required bool pinned,
  }) {
    return chat.copyWith(pinned: pinned);
  }

  static ChatConversation applyArchive(
    ChatConversation chat, {
    required bool archived,
  }) {
    return chat.copyWith(archived: archived);
  }

  static ChatConversation applyUnread(ChatConversation chat) {
    return chat.copyWith(
      unreadCount: chat.unreadCount > 0 ? chat.unreadCount : 1,
    );
  }

  static ChatConversation applyBlocked(
    ChatConversation chat, {
    required bool blocked,
  }) {
    return chat.copyWith(peerBlockedByMe: blocked);
  }
}
