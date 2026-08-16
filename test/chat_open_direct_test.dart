import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_open_direct.dart';
import 'package:han_eat/models/chat_models.dart';

ChatConversation _dm({required int id, required int peerId}) {
  return ChatConversation(
    id: id,
    type: 'direct',
    peer: ChatUserBrief(id: peerId, name: 'User $peerId'),
    updatedAt: DateTime(2026, 8, 16, 12),
  );
}

void main() {
  test('peekAmong returns the DM for that peer', () {
    final chats = [
      ChatConversation(
        id: 1,
        type: 'group',
        title: 'Group',
        updatedAt: DateTime(2026, 8, 16, 12),
      ),
      _dm(id: 9, peerId: 42),
      _dm(id: 3, peerId: 7),
    ];
    expect(ChatOpenDirect.peekAmong(chats, 42)?.id, 9);
    expect(ChatOpenDirect.peekAmong(chats, 7)?.id, 3);
    expect(ChatOpenDirect.peekAmong(chats, 99), isNull);
    expect(ChatOpenDirect.peekAmong(chats, 0), isNull);
  });

  test('peekAmong ignores groups even if a member id matches', () {
    final chats = [
      ChatConversation(
        id: 4,
        type: 'group',
        title: 'Crew',
        membersPreview: const [ChatUserBrief(id: 42, name: ' ann')],
        updatedAt: DateTime(2026, 8, 16, 12),
      ),
    ];
    expect(ChatOpenDirect.peekAmong(chats, 42), isNull);
  });

  test('peekSavedAmong finds the saved chat', () {
    final chats = [
      _dm(id: 2, peerId: 8),
      ChatConversation(
        id: 5,
        type: 'saved',
        updatedAt: DateTime(2026, 8, 16, 12),
      ),
    ];
    expect(ChatOpenDirect.peekSavedAmong(chats)?.id, 5);
    expect(ChatOpenDirect.peekSavedAmong([_dm(id: 2, peerId: 8)]), isNull);
  });
}
