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

  test('stubForPeer uses a negative id derived from the peer', () {
    final stub = ChatOpenDirect.stubForPeer(
      const ChatUserBrief(id: 42, name: 'Ann'),
    );
    expect(ChatOpenDirect.stubIdForPeer(42), -42);
    expect(ChatOpenDirect.isStubId(stub.id), isTrue);
    expect(stub.id, -42);
    expect(stub.type, 'direct');
    expect(stub.peer?.id, 42);
    expect(stub.peer?.name, 'Ann');
  });

  test('peekOrStub returns a stub when the DM is not cached', () {
    expect(
      ChatOpenDirect.peekOrStub(
        11,
        peer: const ChatUserBrief(id: 11, name: 'Bo'),
      )?.id,
      -11,
    );
    expect(ChatOpenDirect.peekOrStub(11), isNull);
    expect(
      ChatOpenDirect.peekOrStub(
        11,
        peer: const ChatUserBrief(id: 99, name: 'Other'),
      ),
      isNull,
    );
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
