import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/referral/pending_referral.dart';
import 'package:han_eat/services/app_invite_service.dart';

void main() {
  setUp(AppInviteService.debugResetOfficialCode);

  test('extracts official code, username and invite URL', () {
    expect(PendingReferral.extract('ABC12XYZ'), 'ABC12XYZ');
    expect(PendingReferral.extract('@alice'), 'alice');
    expect(PendingReferral.extract('u12'), 'u12');
    expect(
      PendingReferral.extract('https://haneat.app/invite?ref=ABC12XYZ'),
      'ABC12XYZ',
    );
    expect(
      PendingReferral.extract('https://haneat.app/register?ref=alice'),
      'alice',
    );
    expect(
      PendingReferral.extract('https://haneat.app/app/invite?ref=ABC12XYZ'),
      'ABC12XYZ',
    );
    expect(
      PendingReferral.extract('https://haneat.app/app/#/invite?ref=ABC12XYZ'),
      'ABC12XYZ',
    );
    expect(PendingReferral.extract(''), isNull);
    expect(PendingReferral.extract(null), isNull);
    expect(
      PendingReferral.extract(
        'https://l.facebook.com/l.php?u=${Uri.encodeComponent('https://haneat.app/invite?ref=ABC12XYZ')}',
      ),
      'ABC12XYZ',
    );
    expect(
      PendingReferral.extract('https://haneat.app/invite?ref=https://haneat.app/invite?ref=ABC12XYZ'),
      'ABC12XYZ',
    );
  });

  test('share URL always uses /invite?ref=', () {
    expect(
      PendingReferral.shareUrl('ABC12XYZ'),
      'https://haneat.app/invite?ref=ABC12XYZ',
    );
  });

  test('invite service prefers the official 8-char code', () {
    expect(AppInviteService.inviteRef(), '');
    AppInviteService.rememberOfficialCode('ABC12XYZ');
    expect(AppInviteService.inviteRef(), 'ABC12XYZ');
    expect(
      AppInviteService.webInviteUrl(),
      'https://haneat.app/invite?ref=ABC12XYZ',
    );
    expect(
      AppInviteService.deepInviteUrl(),
      'haneat://invite?ref=ABC12XYZ',
    );
  });

  test('invite message includes the official link', () {
    AppInviteService.rememberOfficialCode('ABC12XYZ');
    final text = AppInviteService.inviteMessage(inviterName: 'Аня');
    expect(text, contains('https://haneat.app/invite?ref=ABC12XYZ'));
    expect(text, contains('Аня'));
  });
}
