import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_models.dart';

void main() {
  test('copyWith updates admin flags and can clear send restriction', () {
    final until = DateTime(2026, 8, 17, 9);
    const user = ChatUserBrief(
      id: 9,
      name: 'Ann',
      isGroupAdmin: true,
      canInviteUsers: true,
      canManageMembers: true,
      sendRestricted: true,
      sendRestrictionReason: 'spam',
    );
    final restricted = user.copyWith(sendRestrictedUntil: until);
    expect(restricted.sendRestrictedUntil, until);

    final next = restricted.copyWith(
      isGroupAdmin: false,
      canInviteUsers: false,
      canManageMembers: false,
      sendRestricted: false,
      clearSendRestrictedUntil: true,
      clearSendRestrictionReason: true,
    );
    expect(next.id, 9);
    expect(next.name, 'Ann');
    expect(next.isGroupAdmin, isFalse);
    expect(next.canInviteUsers, isFalse);
    expect(next.canManageMembers, isFalse);
    expect(next.sendRestricted, isFalse);
    expect(next.sendRestrictedUntil, isNull);
    expect(next.sendRestrictionReason, isNull);
  });

  test('invite link copyWith marks revoked without dropping token', () {
    final link = ChatGroupInviteLink(
      id: 3,
      token: 'abc',
      inviteLink: 'https://haneat.app/join/abc',
      createdAt: DateTime(2026, 8, 16),
    );
    final revoked = link.copyWith(revokedAt: DateTime(2026, 8, 16, 10));
    expect(revoked.isRevoked, isTrue);
    expect(revoked.token, 'abc');
    expect(revoked.copyWith(clearRevokedAt: true).isRevoked, isFalse);
  });

  test('search item copyWith flips isContact', () {
    const row = ChatUserSearchItem(id: 4, name: 'Bo', isContact: false);
    expect(row.copyWith(isContact: true).isContact, isTrue);
    expect(row.copyWith(isContact: true).name, 'Bo');
  });
}
