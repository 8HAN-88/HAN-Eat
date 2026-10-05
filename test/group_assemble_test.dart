import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/models/chat_models.dart';
import 'package:han_eat/services/chat_service.dart';

void main() {
  test('created group parses web nums and loose member maps', () {
    final conv = ChatService.parseConversation({
      'id': 21.0,
      'type': 'group',
      'title': 'Кухня',
      'member_count': '3',
      'pending_join_requests_count': 1.0,
      'am_i_group_admin': true,
      'am_i_can_manage_members': true,
      'am_i_can_invite_users': true,
      'created_by_user_id': 7.0,
      'members_preview': [
        <dynamic, dynamic>{
          'id': 7.0,
          'name': 'Я',
          'is_group_admin': true,
          'is_group_creator': true,
        },
        <dynamic, dynamic>{
          'id': '11',
          'name': 'Аня',
          'username': 'anya',
        },
        'bad',
      ],
      'last_message': <dynamic, dynamic>{
        'id': 90.0,
        'conversation_id': 21.0,
        'sender_id': 11.0,
        'content': 'Привет',
        'created_at': '2026-01-01T00:00:00.000Z',
        'is_mine': false,
      },
    });
    expect(conv.id, 21);
    expect(conv.isGroup, isTrue);
    expect(conv.displayTitle, 'Кухня');
    expect(conv.memberCount, 3);
    expect(conv.pendingJoinRequestsCount, 1);
    expect(conv.amIGroupAdmin, isTrue);
    expect(conv.amICanInviteUsers, isTrue);
    expect(conv.membersPreview, hasLength(2));
    expect(conv.membersPreview.first.displayName, 'Я');
    expect(conv.membersPreview.first.isGroupCreator, isTrue);
    expect(conv.membersPreview.last.id, 11);
    expect(conv.membersPreview.last.displayName, 'Аня');
    expect(conv.lastMessage?.content, 'Привет');
    expect(ChatThreadRoute.pathFor(conv), '/chats/thread/21');
    expect(ChatGroupInfoRoute.pathFor(conv.id), '/chats/thread/21/info');
  });

  test('inbox keeps assembled groups from loose conversation maps', () {
    final chats = ChatService.parseConversationList({
      'items': [
        <dynamic, dynamic>{
          'id': 21.0,
          'type': 'group',
          'title': 'Кухня',
          'member_count': 3.0,
          'members_preview': [
            <dynamic, dynamic>{'id': 7.0, 'name': 'Я'},
          ],
        },
        <dynamic, dynamic>{'id': 0, 'type': 'group', 'title': 'пустая'},
        'bad',
      ],
    });
    expect(chats, hasLength(1));
    expect(chats.single.isGroup, isTrue);
    expect(chats.single.displayTitle, 'Кухня');
    expect(chats.single.membersPreview.single.displayName, 'Я');
  });

  test('member list and contacts keep loose maps so a group can assemble', () {
    final members = ChatService.parseMemberList({
      'items': [
        <dynamic, dynamic>{
          'id': 7.0,
          'name': 'Я',
          'is_group_admin': true,
          'is_group_creator': true,
        },
        <dynamic, dynamic>{'id': '11', 'name': 'Аня'},
        <dynamic, dynamic>{'id': 0, 'name': 'мусор'},
        'bad',
      ],
    });
    expect(members, hasLength(2));
    expect(members.first.isGroupCreator, isTrue);
    expect(members.last.id, 11);

    final contacts = ChatService.parseContactList({
      'items': [
        <dynamic, dynamic>{
          'id': 4.0,
          'created_at': '2026-01-01T00:00:00.000Z',
          'user': <dynamic, dynamic>{
            'id': 11.0,
            'name': 'Аня',
            'username': 'anya',
          },
        },
        <dynamic, dynamic>{'id': 5.0, 'user': 'bad'},
        'bad',
      ],
    });
    expect(contacts, hasLength(1));
    expect(contacts.single.user.id, 11);
    expect(contacts.single.user.displayName, 'Аня');
    expect(ChatService.parseAddedCount({'added': 2.0}), 2);
    expect(ChatService.parseAddedCount({'count': '3'}), 3);
  });

  test('join invite and add-members keep the assembled group', () {
    final joined = ChatService.parseJoinByInvite({
      'status': 'joined',
      'conversation': <dynamic, dynamic>{
        'id': 21.0,
        'type': 'group',
        'title': 'Кухня',
        'member_count': 4.0,
        'members_preview': [
          <dynamic, dynamic>{'id': 11.0, 'name': 'Аня'},
        ],
      },
    });
    expect(joined.status, 'joined');
    expect(joined.conversation?.isGroup, isTrue);
    expect(joined.conversation?.id, 21);
    expect(joined.conversation?.membersPreview.single.displayName, 'Аня');
    expect(
      ChatThreadRoute.pathFor(joined.conversation!),
      '/chats/thread/21',
    );

    final link = ChatService.parseInviteLink({
      'id': 8.0,
      'token': 'abc',
      'invite_link': 'https://haneat.app/chat-invite/abc',
      'created_at': '2026-01-01T00:00:00.000Z',
      'uses_count': 1.0,
      'max_uses': '20',
    });
    expect(link.token, 'abc');
    expect(link.usesCount, 1);
    expect(link.maxUses, 20);
    expect(link.inviteLink, contains('abc'));

    final requests = ChatService.parseJoinRequestList({
      'items': [
        <dynamic, dynamic>{
          'id': 3.0,
          'status': 'pending',
          'requested_at': '2026-01-01T00:00:00.000Z',
          'user': <dynamic, dynamic>{'id': 15.0, 'name': 'Боря'},
        },
      ],
    });
    expect(requests.single.user.displayName, 'Боря');
  });

  test('empty title and no members cannot assemble a group', () {
    expect(ChatUserBrief.fromJson({'id': 11.0, 'name': 'Аня'}).id, 11);
    expect(
      () => ChatConversation.fromJson({'type': 'direct'}),
      throwsA(isA<FormatException>()),
    );
    final untitled = ChatService.parseConversation({
      'id': 22.0,
      'type': 'group',
    });
    expect(untitled.displayTitle, 'Группа');
    expect(untitled.membersPreview, isEmpty);
  });
}
