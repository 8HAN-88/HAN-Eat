import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_inbox_optimistic.dart';
import 'package:han_eat/models/chat_models.dart';

ChatConversation _chat({
  int unread = 0,
  bool pinned = false,
  bool archived = false,
  bool muted = false,
  DateTime? mutedUntil,
  String notifyMode = 'all',
  bool blocked = false,
}) {
  return ChatConversation(
    id: 7,
    type: 'direct',
    peer: const ChatUserBrief(id: 3, name: 'Ann'),
    updatedAt: DateTime(2026, 8, 16, 12),
    unreadCount: unread,
    pinned: pinned,
    archived: archived,
    muted: muted,
    mutedUntil: mutedUntil,
    notifyMode: notifyMode,
    peerBlockedByMe: blocked,
  );
}

void main() {
  test('applyMute sets timed mute and notify mode', () {
    final until = DateTime(2026, 8, 17, 9);
    final next = ChatInboxOptimistic.applyMute(
      _chat(),
      muted: true,
      until: until,
      notifyMode: 'mentions',
    );
    expect(next.muted, isTrue);
    expect(next.mutedUntil, until);
    expect(next.notifyMode, 'mentions');
  });

  test('applyMute clears until when unmuted', () {
    final next = ChatInboxOptimistic.applyMute(
      _chat(
        muted: true,
        mutedUntil: DateTime(2026, 8, 17, 9),
        notifyMode: 'none',
      ),
      muted: false,
    );
    expect(next.muted, isFalse);
    expect(next.mutedUntil, isNull);
    expect(next.notifyMode, 'all');
  });

  test('applyPin and applyArchive flip flags', () {
    expect(ChatInboxOptimistic.applyPin(_chat(), pinned: true).pinned, isTrue);
    expect(
      ChatInboxOptimistic.applyArchive(_chat(), archived: true).archived,
      isTrue,
    );
  });

  test('applyUnread keeps existing count or sets one', () {
    expect(ChatInboxOptimistic.applyUnread(_chat()).unreadCount, 1);
    expect(ChatInboxOptimistic.applyUnread(_chat(unread: 4)).unreadCount, 4);
  });

  test('applyBlocked toggles peerBlockedByMe', () {
    expect(
      ChatInboxOptimistic.applyBlocked(_chat(), blocked: true).peerBlockedByMe,
      isTrue,
    );
    expect(
      ChatInboxOptimistic.applyBlocked(
        _chat(blocked: true),
        blocked: false,
      ).peerBlockedByMe,
      isFalse,
    );
  });
}
