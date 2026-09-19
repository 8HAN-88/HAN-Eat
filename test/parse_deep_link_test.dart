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

  test('short leftover paths alias to live screens', () {
    expect(shortcutPathAlias('/stars'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/wallet'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/gifts'), StarGiftsInventoryRoute.path);
    expect(shortcutPathAlias('/premium'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/referral'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/partner'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/bots'), MyBotsRoute.path);
    expect(shortcutPathAlias('/security'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/settings/security'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/settings/sessions'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/settings/privacy'), SettingsRoute.path);
    expect(shortcutPathAlias('/blocked'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/saved'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/extra-ads'), ExtraAdsRoute.path);
    expect(shortcutPathAlias('/creator'), CreatorToolsRoute.path);
    expect(shortcutPathAlias('/scheduled'), ScheduledPostsRoute.path);
    expect(shortcutPathAlias('/promoted'), PromotedPostsRoute.path);
    expect(shortcutPathAlias('/payouts'), CreatorRevenueRoute.path);
    expect(shortcutPathAlias('/revenue'), CreatorRevenueRoute.path);
    expect(shortcutPathAlias('/2fa'), TwoFactorSetupRoute.path);
    expect(shortcutPathAlias('/edit-profile'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/profile/edit'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/me/edit'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/privacy'), SettingsRoute.path);
    expect(shortcutPathAlias('/groups'), ChatsRoute.path);
    expect(shortcutPathAlias('/archive'), ChatArchivedRoute.path);
    expect(shortcutPathAlias('/archived'), ChatArchivedRoute.path);
    expect(ChatArchivedRoute.path, '/chats/archived');
    expect(ChatCreateGroupRoute.path, '/chats/new-group');
    expect(ChatNewMessageRoute.path, '/chats/new');
    expect(StoryCreateRoute.path, '/stories/create');
    expect(PaidMessageExceptionsRoute.path, '/settings/paid-exceptions');
    expect(shortcutPathAlias('/new-group'), ChatCreateGroupRoute.path);
    expect(shortcutPathAlias('/new-message'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/people'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/contacts'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/new-channel'), CreateChannelRoute.path);
    expect(shortcutPathAlias('/new-post'), CreatePostRoute.path);
    expect(shortcutPathAlias('/new-reel'), CreateReelRoute.path);
    expect(shortcutPathAlias('/new-story'), StoryCreateRoute.path);
    expect(shortcutPathAlias('/moments'), StoriesRoute.path);
    expect(shortcutPathAlias('/constructor'), FlexConstructorRoute.path);
    expect(shortcutPathAlias('/shop'), FlexShopRoute.path);
    expect(shortcutPathAlias('/admin'), ModerationDashboardRoute.path);
    expect(shortcutPathAlias('/feed'), isNull);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/stars'),
      StarsWalletRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/gifts'),
      StarGiftsInventoryRoute.path,
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
