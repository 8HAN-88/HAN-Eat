import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';

void main() {
  test('PWA /app/ is not a GoRouter location', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/app/?go=1'), isNull);
    expect(
        parseDeepLinkToGoPath('https://www.haneat.app/app/index.html'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/?go=1'), isNull);
  });

  test('strips /app prefix from deep links', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/feed'), '/feed');
    expect(parseDeepLinkToGoPath('https://haneat.app/feed'), '/feed');
    expect(parseDeepLinkToGoPath('https://haneat.app/app/feed?go=1'), '/feed');
  });

  test('reads hash routes on the PWA shell', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/stories'),
      '/stories',
    );
    expect(parseDeepLinkToGoPath('https://haneat.app/app/#/'), isNull);
  });

  test('username links still resolve', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/@alice'),
      UsernameDeepLinkRoute.pathFor('alice'),
    );
  });

  test('invite links keep the referral code', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/invite?ref=ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://www.haneat.app/invite?ref=ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/invite?ref=ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/register?ref=ABC12XYZ'),
      '/register?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('haneat://invite?ref=ABC12XYZ'),
      '/register?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/invite?ref=ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/invite?REF=ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('haneat://invite?REF=ABC12XYZ'),
      '/register?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/invite/ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/invite/ABC12XYZ'),
      '/invite?ref=ABC12XYZ',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/stories'),
      '/stories',
    );
  });

  test('auth email links keep the six-digit code and mailbox', () {
    expect(
      parseDeepLinkToGoPath(
        'haneat://auth/verify-email?token=123456&email=user@test.local',
      ),
      '/verify-email?token=123456&email=user%40test.local',
    );
    expect(
      parseDeepLinkToGoPath(
        'haneat://auth/reset-password?token=654321&email=user@test.local',
      ),
      '/reset-password?token=654321&email=user%40test.local',
    );
  });

  test('short /flex alias stays a flex path in deep links', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/flex'), '/flex');
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/flex'),
      '/flex',
    );
  });

  test('blocked list has a settings path', () {
    expect(BlockedUsersRoute.path, '/settings/blocked');
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/settings/blocked'),
      '/settings/blocked',
    );
  });

  test('singular channel paid paths alias to /channels/:id', () {
    expect(
      channelPaidPathAlias('/channel/1/giveaways'),
      '/channels/1/giveaways',
    );
    expect(
      channelPaidPathAlias('/channel/7/suggested-posts', 'manage=1'),
      '/channels/7/suggested-posts?manage=1',
    );
    expect(channelPaidPathAlias('/channel/1/info'), isNull);
    expect(channelPaidPathAlias('/channels/1/giveaways'), isNull);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/channel/1/giveaways'),
      '/channels/1/giveaways',
    );
    expect(
      parseDeepLinkToGoPath(
        'https://haneat.app/app/#/channel/4/suggested-posts?name=HAN',
      ),
      '/channels/4/suggested-posts?name=HAN',
    );
  });

  test('reel share links open /reel/:id', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/reel/28'), '/reel/28');
    expect(parseDeepLinkToGoPath('https://haneat.app/app/reel/28'), '/reel/28');
    expect(parseDeepLinkToGoPath('haneat://reel/28'), '/reel/28');
  });

  test('HTML forgot-password on localhost opens the Flutter screen', () {
    expect(
      parseDeepLinkToGoPath(
        'http://127.0.0.1:8088/forgot-password?flutter=1&email=user@test.local',
      ),
      '/forgot-password?email=user%40test.local',
    );
    expect(
      parseDeepLinkToGoPath(
        'https://haneat.app/app/forgot-password?flutter=1&email=user@test.local',
      ),
      '/forgot-password?email=user%40test.local',
    );
    expect(
      parseDeepLinkToGoPath(
        'http://localhost:8088/verify-email?flutter=1&email=user@test.local',
      ),
      '/verify-email?email=user%40test.local',
    );
  });
}
