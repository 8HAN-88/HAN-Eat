import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/features/bots/presentation/bot_detail_screen.dart';

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
    expect(shortcutPathAlias('/help'), SupportContactRoute.path);
    expect(shortcutPathAlias('/faq'), SupportContactRoute.path);
    expect(shortcutPathAlias('/tickets'), SupportContactRoute.path);
    expect(shortcutPathAlias('/about'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/legal'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/terms'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/inbox'), NotificationsRoute.path);
    expect(shortcutPathAlias('/messages'), ChatsRoute.path);
    expect(shortcutPathAlias('/dm'), ChatsRoute.path);
    expect(shortcutPathAlias('/theme'), SettingsRoute.path);
    expect(shortcutPathAlias('/appearance'), SettingsRoute.path);
    expect(shortcutPathAlias('/compose'), CreatePostRoute.path);
    expect(shortcutPathAlias('/write'), CreatePostRoute.path);
    expect(shortcutPathAlias('/camera'), StoryCreateRoute.path);
    expect(shortcutPathAlias('/folders'), ChatFolderNewRoute.path);
    expect(shortcutPathAlias('/new-folder'), ChatFolderNewRoute.path);
    expect(ChatFolderNewRoute.path, '/chats/folders/new');
    expect(ChatFolderEditRoute.pathFor(7), '/chats/folders/7');
    expect(ChatFolderNewRoute.idsFrom('1, 2,x,3'), [1, 2, 3]);
    expect(ChatMediaGalleryRoute.pathFor(22), '/chats/thread/22/media');
    expect(ChatGroupInfoRoute.pathFor(22), '/chats/thread/22/info');
    expect(StickerPackManageRoute.pathFor(4), '/stickers/4');
    expect(StickerPackPreviewRoute.pathFor('cute'), '/addstickers/cute');
    expect(shortcutPathAlias('/sessions'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/devices'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/language'), SettingsRoute.path);
    expect(shortcutPathAlias('/lang'), SettingsRoute.path);
    expect(shortcutPathAlias('/data'), SettingsRoute.path);
    expect(shortcutPathAlias('/storage'), SettingsRoute.path);
    expect(shortcutPathAlias('/themes'), SettingsRoute.path);
    expect(shortcutPathAlias('/night'), SettingsRoute.path);
    expect(shortcutPathAlias('/proxy'), SettingsRoute.path);
    expect(shortcutPathAlias('/saved-messages'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/calls'), ChatsRoute.path);
    expect(shortcutPathAlias('/stickers'), ChatsRoute.path);
    expect(shortcutPathAlias('/blocklist'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/notification-settings'),
        NotificationSettingsRoute.path);
    expect(shortcutPathAlias('/notif-settings'), NotificationSettingsRoute.path);
    expect(shortcutPathAlias('/export'), BackupRoute.path);
    expect(StoryViewerRoute.pathFor(9), '/stories/9');
    expect(ChannelSearchRoute.pathFor(1), '/channel/1/search');
    expect(ChatGroupModerationLogRoute.pathFor(22), '/chats/thread/22/log');
    expect(MiniAppOpenRoute.pathFor(3), '/webapp/3');
    expect(
      DonateRoute.pathFor(recipientId: 11, recipientName: 'Админ'),
      '/donate?to=11&name=%D0%90%D0%B4%D0%BC%D0%B8%D0%BD',
    );
    expect(shortcutPathAlias('/marketplace'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/qr'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/scan'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/gif'), ChatsRoute.path);
    expect(shortcutPathAlias('/emoji'), ChatsRoute.path);
    expect(shortcutPathAlias('/webapp'), MiniAppsRoute.path);
    expect(shortcutPathAlias('/miniapp'), MiniAppsRoute.path);
    expect(shortcutPathAlias('/privacy-policy'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/tos'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/cookies'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/settings/language'), SettingsRoute.path);
    expect(shortcutPathAlias('/settings/data'), SettingsRoute.path);
    expect(shortcutPathAlias('/settings/storage'), SettingsRoute.path);
    expect(SavedPostsRoute.path, '/saved-posts');
    expect(shortcutPathAlias('/stats'), AppAnalyticsRoute.path);
    expect(shortcutPathAlias('/insights'), AppAnalyticsRoute.path);
    expect(shortcutPathAlias('/bookmarks'), SavedPostsRoute.path);
    expect(shortcutPathAlias('/likes'), SavedPostsRoute.path);
    expect(shortcutPathAlias('/saved-posts'), SavedPostsRoute.path);
    expect(shortcutPathAlias('/mentions'), NotificationsRoute.path);
    expect(shortcutPathAlias('/activity'), NotificationsRoute.path);
    expect(shortcutPathAlias('/settings/backup'), BackupRoute.path);
    expect(shortcutPathAlias('/settings/2fa'), TwoFactorSetupRoute.path);
    expect(shortcutPathAlias('/settings/devices'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/download'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/licenses'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/changelog'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/version'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/wallpaper'), SettingsRoute.path);
    expect(shortcutPathAlias('/autodelete'), SettingsRoute.path);
    expect(shortcutPathAlias('/chat-settings'), SettingsRoute.path);
    expect(shortcutPathAlias('/data-and-storage'), SettingsRoute.path);
    expect(shortcutPathAlias('/giveaway'), AdsHubRoute.path);
    expect(shortcutPathAlias('/giveaways'), AdsHubRoute.path);
    expect(shortcutPathAlias('/boost'), AdsHubRoute.path);
    expect(shortcutPathAlias('/botfather'), MyBotsRoute.path);
    expect(shortcutPathAlias('/newbot'), MyBotsRoute.path);
    expect(shortcutPathAlias('/gifts/market'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/gifts/shop'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/secret'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/passcode'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/passport'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/poll'), CreatePostRoute.path);
    expect(shortcutPathAlias('/nearby'), ChatsRoute.path);
    expect(shortcutPathAlias('/home'), FeedRoute.path);
    expect(shortcutPathAlias('/explore'), FeedRoute.path);
    expect(shortcutPathAlias('/signin'), LoginRoute.path);
    expect(shortcutPathAlias('/signup'), RegisterRoute.path);
    expect(shortcutPathAlias('/contact'), SupportContactRoute.path);
    expect(shortcutPathAlias('/studio'), CreatorToolsRoute.path);
    expect(shortcutPathAlias('/billing'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/ai'), FlexSubscriptionRoute.pathWithLevel(9));
    expect(shortcutPathAlias('/pro'), FlexSubscriptionRoute.pathWithLevel(18));
    expect(shortcutPathAlias('/max'), FlexSubscriptionRoute.pathWithLevel(79));
    expect(shortcutPathAlias('/advertiser'), AdsHubRoute.path);
    expect(shortcutPathAlias('/queue'), ModerationQueueRoute.path);
    expect(shortcutPathAlias('/refunds'), AdminRefundQueueRoute.path);
    expect(shortcutPathAlias('/affiliate'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/collectibles'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/tip'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/features'), FlexConstructorRoute.path);
    expect(shortcutPathAlias('/publish'), CreatePostRoute.path);
    expect(shortcutPathAlias('/import'), BackupRoute.path);
    expect(shortcutPathAlias('/gdpr'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/exceptions'), PaidMessageExceptionsRoute.path);
    expect(shortcutPathAlias('/add-contact'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/invite-friends'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/active-sessions'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/two-step'), TwoFactorSetupRoute.path);
    expect(shortcutPathAlias('/email'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/highlights'), StoriesRoute.path);
    expect(shortcutPathAlias('/catalog'), ChatsRoute.path);
    expect(shortcutPathAlias('/find'), SearchRoute.path);
    expect(shortcutPathAlias('/drafts'), ScheduledPostsRoute.path);
    expect(shortcutPathAlias('/comments'), NotificationsRoute.path);
    expect(shortcutPathAlias('/bot'), MyBotsRoute.path);
    expect(shortcutPathAlias('/settings/flex'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/settings/about'), SupportSecurityRoute.path);
    expect(botSectionPathAlias('/bots/5/commands'), '/bots/5/commands');
    expect(botSectionPathAlias('/bots/5/command'), '/bots/5/commands');
    expect(botSectionPathAlias('/bots/5/apps'), '/bots/5/apps');
    expect(botSectionPathAlias('/bots/5/miniapps'), '/bots/5/apps');
    expect(botSectionPathAlias('/bots/5/token'), '/bots/5?section=token');
    expect(botSectionPathAlias('/bots/5/newapp'), '/bots/5/apps?new=1');
    expect(botSectionPathAlias('/bots/5/webhook'), '/bots/5');
    expect(botSectionPathAlias('/bots/my/commands'), isNull);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/bots/5/commands'),
      '/bots/5/commands',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/bots/5/miniapps'),
      '/bots/5/apps',
    );
    expect(BotCommandsRoute.pathFor(5, username: 'demo_bot'),
        '/bots/5/commands?u=demo_bot');
    expect(BotMiniAppsRoute.pathFor(5, newApp: true), '/bots/5/apps?new=1');
    expect(
      BotDetailRoute.pathFor(5, section: BotDetailOpenSection.commands),
      '/bots/5/commands',
    );
    expect(
      BotDetailRoute.pathFor(5, section: BotDetailOpenSection.newApp),
      '/bots/5/apps?new=1',
    );
    expect(shortcutPathAlias('/miniapps'), MiniAppsRoute.path);
    expect(shortcutPathAlias('/my-bots'), MyBotsRoute.path);
    expect(shortcutPathAlias('/balance'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/subscribe'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/flex-pro'), FlexSubscriptionRoute.pathWithLevel(18));
    expect(shortcutPathAlias('/create-group'), ChatCreateGroupRoute.path);
    expect(shortcutPathAlias('/blacklist'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/two-factor'), TwoFactorSetupRoute.path);
    expect(shortcutPathAlias('/my-channels'), ChannelsManagementRoute.path);
    expect(shortcutPathAlias('/paid-messages'), PaidMessageExceptionsRoute.path);
    expect(shortcutPathAlias('/collections'), SavedPostsRoute.path);
    expect(shortcutPathAlias('/settings/close-friends'), CloseFriendsRoute.path);
    expect(shortcutPathAlias('/my-stars'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/flex-shop'), FlexShopRoute.path);
    expect(shortcutPathAlias('/join-group'), ChatCreateGroupRoute.path);
    expect(resourcePathAlias('/channels/1'), '/channel/1');
    expect(resourcePathAlias('/channels/1/info'), '/channel/1/info');
    expect(resourcePathAlias('/channels/1/giveaways'), isNull);
    expect(resourcePathAlias('/channels/management'), isNull);
    expect(resourcePathAlias('/chats/21'), '/chats/thread/21');
    expect(resourcePathAlias('/chat/21'), '/chats/thread/21');
    expect(resourcePathAlias('/chats/archived'), isNull);
    expect(resourcePathAlias('/chats/21/info'), '/chats/thread/21/info');
    expect(resourcePathAlias('/chats/thread/21/members'), '/chats/thread/21/info');
    expect(resourcePathAlias('/chats/thread/21/search'), '/chats/thread/21');
    expect(resourcePathAlias('/invoice/9'), '/paid/invoices/9');
    expect(resourcePathAlias('/paid/invoice/9'), '/paid/invoices/9');
    expect(resourcePathAlias('/join/AbC12'), '/chat-invite/AbC12');
    expect(resourcePathAlias('/user/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/profile/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/profile/followers'), isNull);
    expect(resourcePathAlias('/c/1'), '/channel/1');
    expect(resourcePathAlias('/posts/28/comments'), '/post/28/comments');
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/chats/21'),
      '/chats/thread/21',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/channels/1/settings'),
      '/channel/1/settings',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/invoice/9'),
      '/paid/invoices/9',
    );
    expect(resourcePathAlias('/miniapp/5'), '/webapp/5');
    expect(resourcePathAlias('/mini-apps/5'), '/webapp/5');
    expect(resourcePathAlias('/bot/5'), '/bots/5');
    expect(botSectionPathAlias('/bot/5/commands'), '/bots/5/commands');
    expect(resourcePathAlias('/folder/3'), '/chats/folders/3');
    expect(resourcePathAlias('/sticker/4'), '/stickers/4');
    expect(resourcePathAlias('/pack/cute'), '/addstickers/cute');
    expect(resourcePathAlias('/moment/9'), '/stories/9');
    expect(resourcePathAlias('/moments/create'), StoryCreateRoute.path);
    expect(resourcePathAlias('/donate/11'), '/donate?to=11');
    expect(resourcePathAlias('/tip/11'), '/donate?to=11');
    expect(resourcePathAlias('/campaign/8'), '/ads/8');
    expect(resourcePathAlias('/group/21'), '/chats/thread/21');
    expect(resourcePathAlias('/hashtag/han'), '${SearchRoute.path}?q=%23han');
    expect(resourcePathAlias('/p/28'), '/post/28');
    expect(resourcePathAlias('/ch/1'), '/channel/1');
    expect(shortcutPathAlias('/new-ad'), AdsCampaignEditorRoute.path);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/miniapp/5'),
      '/webapp/5',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/donate/11'),
      '/donate?to=11',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/bot/5/apps'),
      '/bots/5/apps',
    );
    expect(
      resourcePathAlias('/profile/11/followers'),
      ProfileFollowersRoute.withUserId(11),
    );
    expect(
      resourcePathAlias('/user/11/following'),
      ProfileFollowingRoute.withUserId(11),
    );
    expect(resourcePathAlias('/followers/11'),
        ProfileFollowersRoute.withUserId(11));
    expect(resourcePathAlias('/u/alice/followers'),
        UsernameDeepLinkRoute.pathFor('alice'));
    expect(resourcePathAlias('/channel/1/posts'), '/channel/1');
    expect(resourcePathAlias('/channels/1/feed'), '/channel/1');
    expect(resourcePathAlias('/post/28/likes'), '/post/28');
    expect(resourcePathAlias('/b/5'), '/bots/5');
    expect(resourcePathAlias('/w/5'), '/webapp/5');
    expect(resourcePathAlias('/d/11'), '/donate?to=11');
    expect(resourcePathAlias('/f/3'), '/chats/folders/3');
    expect(resourcePathAlias('/t/21'), '/chats/thread/21');
    expect(resourcePathAlias('/gifts/9'), StarGiftsInventoryRoute.path);
    expect(resourcePathAlias('/gifts/market'), isNull);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/profile/11/followers'),
      ProfileFollowersRoute.withUserId(11),
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/channel/1/posts'),
      '/channel/1',
    );
    expect(resourcePathAlias('/chat/21/media'), '/chats/thread/21/media');
    expect(resourcePathAlias('/dm/21/info'), '/chats/thread/21/info');
    expect(resourcePathAlias('/group/21/info'), '/chats/thread/21/info');
    expect(
      resourcePathAlias('/chats/thread/21/gallery'),
      '/chats/thread/21/media',
    );
    expect(resourcePathAlias('/video/28'), '/post/28');
    expect(resourcePathAlias('/photo/28'), '/post/28');
    expect(resourcePathAlias('/comments/28'), '/post/28/comments');
    expect(
      resourcePathAlias('/post/28/analytics'),
      AppAnalyticsRoute.pathWithPostId(28),
    );
    expect(
      resourcePathAlias('/stats/28'),
      AppAnalyticsRoute.pathWithPostId(28),
    );
    expect(resourcePathAlias('/bot/5/edit'), '/bots/5');
    expect(resourcePathAlias('/c/1/info'), '/channel/1/info');
    expect(resourcePathAlias('/c/1/settings'), '/channel/1/settings');
    expect(resourcePathAlias('/ch/1/subscribers'), '/channel/1/subscribers');
    expect(resourcePathAlias('/channel/1/members'), '/channel/1/subscribers');
    expect(resourcePathAlias('/p/28/comments'), '/post/28/comments');
    expect(resourcePathAlias('/p/28/edit'), '/post/28/edit');
    expect(resourcePathAlias('/p/28/likes'), '/post/28');
    expect(
      resourcePathAlias('/posts/28/likes'),
      '/post/28',
    );
    expect(resourcePathAlias('/t/21/info'), '/chats/thread/21/info');
    expect(resourcePathAlias('/g/21/media'), '/chats/thread/21/media');
    expect(resourcePathAlias('/f/3/edit'), '/chats/folders/3');
    expect(resourcePathAlias('/folder/3/edit'), '/chats/folders/3');
    expect(resourcePathAlias('/direct/21'), '/chats/thread/21');
    expect(resourcePathAlias('/direct/t/21'), '/chats/thread/21');
    expect(resourcePathAlias('/im/21'), '/chats/thread/21');
    expect(resourcePathAlias('/im/21/info'), '/chats/thread/21/info');
    expect(resourcePathAlias('/msg/21'), '/chats/thread/21');
    expect(resourcePathAlias('/thread/21/media'), '/chats/thread/21/media');
    expect(resourcePathAlias('/peer/11'), '${ProfileRoute.path}?userId=11');
    expect(botSectionPathAlias('/b/5/commands'), '/bots/5/commands');
    expect(botSectionPathAlias('/b/5/apps'), '/bots/5/apps');
    expect(channelPaidPathAlias('/c/1/giveaways'), '/channels/1/giveaways');
    expect(channelPaidPathAlias('/ch/1/suggested-posts'),
        '/channels/1/suggested-posts');
    expect(shortcutPathAlias('/direct'), ChatsRoute.path);
    expect(shortcutPathAlias('/direct/inbox'), ChatsRoute.path);
    expect(shortcutPathAlias('/im'), ChatsRoute.path);
    expect(shortcutPathAlias('/me'), ProfileTabRoute.path);
    expect(resourcePathAlias('/c/1/post/28'), '/channel/1/post/28');
    expect(resourcePathAlias('/c/1/28'), '/channel/1/post/28');
    expect(resourcePathAlias('/ch/1/post/28/edit'), '/channel/1/post/28/edit');
    expect(
      resourcePathAlias('/channel/1/post/28/comments'),
      '/post/28/comments',
    );
    expect(
      resourcePathAlias('/channels/1/members'),
      '/channel/1/subscribers',
    );
    expect(
      resourcePathAlias('/channels/1/post/28/comments'),
      '/post/28/comments',
    );
    expect(resourcePathAlias('/post/28/share'), '/post/28');
    expect(resourcePathAlias('/p/28/repost'), '/post/28');
    expect(resourcePathAlias('/video/28/comments'), '/post/28/comments');
    expect(resourcePathAlias('/stickerpack/cute'), '/addstickers/cute');
    expect(shortcutPathAlias('/dialogs'), ChatsRoute.path);
    expect(shortcutPathAlias('/channel'), ChannelsManagementRoute.path);
    expect(shortcutPathAlias('/new-dm'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/privacy/last-seen'), SettingsRoute.path);
    expect(
      shortcutPathAlias('/settings/notif'),
      NotificationSettingsRoute.path,
    );
    expect(resourcePathAlias('/dialogs/21'), '/chats/thread/21');
    expect(resourcePathAlias('/m/21'), '/chats/thread/21');
    expect(resourcePathAlias('/chats/thread/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/chats/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/share/post/28'), '/post/28');
    expect(resourcePathAlias('/share/reel/28'), '/reel/28');
    expect(resourcePathAlias('/call/21'), '/chats/thread/21');
    expect(resourcePathAlias('/saved/21'), '/chats/thread/21');
    expect(unwrapGoOpenPath('/go/c/1/info'), '/c/1/info');
    expect(unwrapGoOpenPath('/open/chats/21'), '/chats/21');
    expect(leftoverPathAlias('/go/c/1/info'), '/channel/1/info');
    expect(leftoverPathAlias('/open/share/post/28'), '/post/28');
    expect(leftoverPathAlias('/c/1/giveaways'), '/channels/1/giveaways');
    expect(shortcutPathAlias('/go'), ChatsRoute.path);
    expect(resourcePathAlias('/r/28'), '/reel/28');
    expect(resourcePathAlias('/contact/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/people/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/boost/1'), '/channel/1');
    expect(resourcePathAlias('/forward/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/reply/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/quote/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/topic/21'), '/chats/thread/21');
    expect(resourcePathAlias('/forum/21'), '/chats/thread/21');
    expect(resourcePathAlias('/n/9'), NotificationsRoute.path);
    expect(resourcePathAlias('/highlights/9'), '/stories/9');
    expect(resourcePathAlias('/poll/28'), '/post/28');
    expect(resourcePathAlias('/voice/28'), '/post/28');
    expect(resourcePathAlias('/file/28'), '/post/28');
    expect(resourcePathAlias('/doc/28'), '/post/28');
    expect(resourcePathAlias('/live/1'), '/channel/1');
    expect(resourcePathAlias('/stream/1'), '/channel/1');
    expect(shortcutPathAlias('/location'), ChatsRoute.path);
    expect(shortcutPathAlias('/live'), ChannelsManagementRoute.path);
    expect(shortcutPathAlias('/stream'), ChannelsManagementRoute.path);
    expect(resourcePathAlias('/receipt/9'), '/paid/invoices/9');
    expect(resourcePathAlias('/bill/9'), '/paid/invoices/9');
    expect(shortcutPathAlias('/privacy/blocked'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/settings/blocklist'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/topic'), ChatsRoute.path);
    expect(shortcutPathAlias('/forum'), ChatsRoute.path);
    expect(shortcutPathAlias('/boost'), AdsHubRoute.path);
    expect(shortcutPathAlias('/people'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/black-list'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/close-friend'), CloseFriendsRoute.path);
    expect(resourcePathAlias('/l/1'), '/channel/1');
    expect(resourcePathAlias('/a/8'), '/ads/8');
    expect(resourcePathAlias('/v/28'), '/post/28');
    expect(resourcePathAlias('/voicechat/1'), '/channel/1');
    expect(resourcePathAlias('/voice-chat/1'), '/channel/1');
    expect(resourcePathAlias('/vc/1'), '/channel/1');
    expect(resourcePathAlias('/saved-messages/21'), '/chats/thread/21');
    expect(resourcePathAlias('/modlog/21'), '/chats/thread/21/log');
    expect(resourcePathAlias('/adminlog/21'), '/chats/thread/21/log');
    expect(resourcePathAlias('/subscribers/1'), '/channel/1/subscribers');
    expect(resourcePathAlias('/boosts/1'), '/channel/1');
    expect(resourcePathAlias('/reactions/28'), '/post/28');
    expect(resourcePathAlias('/likes/28'), '/post/28');
    expect(resourcePathAlias('/forward/28'), '/post/28');
    expect(resourcePathAlias('/edit/28'), '/post/28/edit');
    expect(resourcePathAlias('/block/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/secret/21'), '/chats/thread/21');
    expect(resourcePathAlias('/mute/21'), '/chats/thread/21');
    expect(resourcePathAlias('/gif/28'), '/post/28');
    expect(resourcePathAlias('/round/28'), '/post/28');
    expect(resourcePathAlias('/link/AbC12'), '/chat-invite/AbC12');
    expect(resourcePathAlias('/share/sticker/4'), '/stickers/4');
    expect(resourcePathAlias('/share/gift/9'), StarGiftsInventoryRoute.path);
    expect(resourcePathAlias('/share/invoice/9'), '/paid/invoices/9');
    expect(resourcePathAlias('/share/miniapp/5'), '/webapp/5');
    expect(resourcePathAlias('/share/folder/3'), '/chats/folders/3');
    expect(shortcutPathAlias('/privacy/profile'), SettingsRoute.path);
    expect(shortcutPathAlias('/privacy/birthday'), SettingsRoute.path);
    expect(shortcutPathAlias('/settings/appearance'), SettingsRoute.path);
    expect(shortcutPathAlias('/settings/privacy/blocked'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/extraads'), ExtraAdsRoute.path);
    expect(shortcutPathAlias('/voice-chats'), ChatsRoute.path);
    expect(shortcutPathAlias('/ads-review'), AdsReviewRoute.path);
    expect(shortcutPathAlias('/admin-tickets'), AdminSupportTicketsRoute.path);
    expect(shortcutPathAlias('/partner-payouts'), AdminPartnerPayoutsRoute.path);
    expect(shortcutPathAlias('/creator-payouts'), AdminCreatorPayoutsRoute.path);
    expect(shortcutPathAlias('/flex-features'), AdminFlexFeaturesRoute.path);
    expect(shortcutPathAlias('/my-moments'), StoriesRoute.path);
    expect(shortcutPathAlias('/log-in'), LoginRoute.path);
    expect(leftoverPathAlias('/go/l/1'), '/channel/1');
    expect(leftoverPathAlias('/open/modlog/21'), '/chats/thread/21/log');
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/voicechat/1'),
      '/channel/1',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/edit/28'),
      '/post/28/edit',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/settings/appearance'),
      SettingsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/share/miniapp/5'),
      '/webapp/5',
    );
    expect(resourcePathAlias('/c/1/boost'), '/channel/1');
    expect(resourcePathAlias('/channel/1/live'), '/channel/1');
    expect(resourcePathAlias('/channels/1/voicechat'), '/channel/1');
    expect(resourcePathAlias('/chat/21/call'), '/chats/thread/21');
    expect(resourcePathAlias('/dm/21/voice'), '/chats/thread/21');
    expect(resourcePathAlias('/chats/thread/21/video'), '/chats/thread/21');
    expect(
      resourcePathAlias('/profile/11/stories'),
      ProfileRoute.withUserId(11),
    );
    expect(
      resourcePathAlias('/user/11/moments'),
      ProfileRoute.withUserId(11),
    );
    expect(
      resourcePathAlias('/u/alice/highlights'),
      UsernameDeepLinkRoute.pathFor('alice'),
    );
    expect(resourcePathAlias('/gift/9/send'), StarGiftsInventoryRoute.path);
    expect(resourcePathAlias('/share/ad/8'), '/ads/8');
    expect(resourcePathAlias('/share/giveaway/1'), '/channel/1');
    expect(resourcePathAlias('/q/28'), '/post/28');
    expect(resourcePathAlias('/quiz/28'), '/post/28');
    expect(resourcePathAlias('/iv/28'), '/post/28');
    expect(resourcePathAlias('/j/AbC12'), '/chat-invite/AbC12');
    expect(resourcePathAlias('/emoji/cute'), '/addstickers/cute');
    expect(resourcePathAlias('/addemoji/cute'), '/addstickers/cute');
    expect(
      resourcePathAlias('/collectible/9'),
      StarGiftsInventoryRoute.path,
    );
    expect(resourcePathAlias('/theme/1'), SettingsRoute.path);
    expect(shortcutPathAlias('/quiz'), CreatePostRoute.path);
    expect(shortcutPathAlias('/settings/privacy/calls'), SettingsRoute.path);
    expect(shortcutPathAlias('/privacy/invites'), SettingsRoute.path);
    expect(shortcutPathAlias('/passkeys'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/ton'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/fragment'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/newmessage'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/savedmessages'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/addstickers'), ChatsRoute.path);
    expect(
      leftoverPathAlias('/go/c/1/boost'),
      '/channel/1',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/chat/21/call'),
      '/chats/thread/21',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/quiz/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/ton'),
      StarsWalletRoute.path,
    );
    expect(resourcePathAlias('/c/1/stats'), '/channel/1');
    expect(resourcePathAlias('/channel/1/invite'), '/channel/1/info');
    expect(resourcePathAlias('/chat/21/invite'), '/chats/thread/21/info');
    expect(resourcePathAlias('/post/28/views'), '/post/28');
    expect(resourcePathAlias('/p/28/forwards'), '/post/28');
    expect(resourcePathAlias('/views/28'), '/post/28');
    expect(resourcePathAlias('/filter/3'), '/chats/folders/3');
    expect(resourcePathAlias('/chatfolder/3'), '/chats/folders/3');
    expect(resourcePathAlias('/folderinvite/AbC12'), '/chat-invite/AbC12');
    expect(shortcutPathAlias('/newgroup'), ChatCreateGroupRoute.path);
    expect(shortcutPathAlias('/newchannel'), CreateChannelRoute.path);
    expect(shortcutPathAlias('/newchat'), ChatNewMessageRoute.path);
    expect(shortcutPathAlias('/newpost'), CreatePostRoute.path);
    expect(shortcutPathAlias('/create-recipe'), CreatePostRoute.path);
    expect(shortcutPathAlias('/newstory'), StoryCreateRoute.path);
    expect(shortcutPathAlias('/newreel'), CreateReelRoute.path);
    expect(shortcutPathAlias('/confirm-email'), VerifyEmailRoute.path);
    expect(shortcutPathAlias('/forgot-pass'), ForgotPasswordRoute.path);
    expect(shortcutPathAlias('/twofa'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/setusername'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/lite-mode'), SettingsRoute.path);
    expect(shortcutPathAlias('/success'), SubscriptionSuccessRoute.path);
    expect(shortcutPathAlias('/cancel'), SubscriptionCancelRoute.path);
    expect(shortcutPathAlias('/checkout'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/paid-success'), StarsCheckoutSuccessRoute.path);
    expect(
      leftoverPathAlias('/go/c/1/stats'),
      '/channel/1',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/newgroup'),
      ChatCreateGroupRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/post/28/views'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/confirm-email'),
      VerifyEmailRoute.path,
    );
    expect(resourcePathAlias('/c/1/boosts'), '/channel/1');
    expect(resourcePathAlias('/channel/1/statistics'), '/channel/1');
    expect(resourcePathAlias('/story/9'), '/stories/9');
    expect(resourcePathAlias('/status/9'), '/stories/9');
    expect(resourcePathAlias('/startapp/5'), '/webapp/5');
    expect(resourcePathAlias('/startbot/5'), '/bots/5');
    expect(resourcePathAlias('/bot/5/start'), '/bots/5');
    expect(resourcePathAlias('/stars/pay/9'), '/paid/invoices/9');
    expect(shortcutPathAlias('/buy'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/topup'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/ref'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/helpdesk'), SupportContactRoute.path);
    expect(shortcutPathAlias('/nightmode'), SettingsRoute.path);
    expect(shortcutPathAlias('/chatlist'), ChatsRoute.path);
    expect(shortcutPathAlias('/newfolder'), ChatFolderNewRoute.path);
    expect(shortcutPathAlias('/consent'), LegalConsentRoute.path);
    expect(shortcutPathAlias('/otp'), LoginRoute.path);
    expect(shortcutPathAlias('/mygifts'), StarGiftsInventoryRoute.path);
    expect(shortcutPathAlias('/mybots'), MyBotsRoute.path);
    expect(shortcutPathAlias('/mychannels'), ChannelsManagementRoute.path);
    expect(shortcutPathAlias('/closefriends'), CloseFriendsRoute.path);
    expect(shortcutPathAlias('/flexplus'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/tg'), ChatsRoute.path);
    expect(shortcutPathAlias('/startapp'), MiniAppsRoute.path);
    expect(shortcutPathAlias('/status'), StoriesRoute.path);
    expect(
      leftoverPathAlias('/go/story/9'),
      '/stories/9',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/startapp/5'),
      '/webapp/5',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/story/9'),
      '/stories/9',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/buy'),
      StarsWalletRoute.path,
    );
    expect(resourcePathAlias('/openpost/28'), '/post/28');
    expect(resourcePathAlias('/openchat/21'), '/chats/thread/21');
    expect(resourcePathAlias('/openchannel/1'), '/channel/1');
    expect(resourcePathAlias('/openbot/5'), '/bots/5');
    expect(resourcePathAlias('/openuser/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/openstory/9'), '/stories/9');
    expect(resourcePathAlias('/react/28'), '/post/28');
    expect(resourcePathAlias('/view/28'), '/post/28');
    expect(resourcePathAlias('/unique/9'), StarGiftsInventoryRoute.path);
    expect(resourcePathAlias('/nft/9'), StarGiftsInventoryRoute.path);
    expect(resourcePathAlias('/share/startapp/5'), '/webapp/5');
    expect(shortcutPathAlias('/mtproto'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/terms-of-service'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/report-abuse'), SupportContactRoute.path);
    expect(shortcutPathAlias('/payout-settings'), CreatorRevenueRoute.path);
    expect(shortcutPathAlias('/billing-history'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/gift-premium'), FlexSubscriptionRoute.path);
    expect(shortcutPathAlias('/send-stars'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/calllog'), ChatsRoute.path);
    expect(shortcutPathAlias('/secretchats'), ChatsRoute.path);
    expect(shortcutPathAlias('/verify-account'), ProfileAuthRoute.path);
    expect(resourcePathAlias('/open-post/28'), '/post/28');
    expect(resourcePathAlias('/open-chat/21'), '/chats/thread/21');
    expect(resourcePathAlias('/open-channel/1'), '/channel/1');
    expect(resourcePathAlias('/open-bot/5'), '/bots/5');
    expect(resourcePathAlias('/open-user/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/open-story/9'), '/stories/9');
    expect(resourcePathAlias('/open-reel/28'), '/reel/28');
    expect(resourcePathAlias('/linkedchat/1'), '/channel/1');
    expect(resourcePathAlias('/linked-chat/1'), '/channel/1');
    expect(resourcePathAlias('/gigagroup/21'), '/chats/thread/21');
    expect(resourcePathAlias('/megagroup/21'), '/chats/thread/21');
    expect(resourcePathAlias('/start-bot/5'), '/bots/5');
    expect(resourcePathAlias('/start-app/5'), '/webapp/5');
    expect(resourcePathAlias('/share/start-bot/5'), '/bots/5');
    expect(resourcePathAlias('/share/contact/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/chat/21/mute'), '/chats/thread/21');
    expect(resourcePathAlias('/dm/21/pin'), '/chats/thread/21');
    expect(resourcePathAlias('/chats/thread/21/secret'), '/chats/thread/21');
    expect(resourcePathAlias('/gigagroup/21/info'), '/chats/thread/21/info');
    expect(shortcutPathAlias('/call-log'), ChatsRoute.path);
    expect(shortcutPathAlias('/recent-calls'), ChatsRoute.path);
    expect(shortcutPathAlias('/secret-chats'), ChatsRoute.path);
    expect(shortcutPathAlias('/saved-msg'), ChatsRoute.path);
    expect(shortcutPathAlias('/im-box'), ChatsRoute.path);
    expect(shortcutPathAlias('/terms-of-use'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/refunds-policy'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/dmca'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/ban-appeal'), SupportContactRoute.path);
    expect(shortcutPathAlias('/kyc'), ProfileAuthRoute.path);
    expect(shortcutPathAlias('/invoice-history'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/gift-stars'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/start-bot'), MyBotsRoute.path);
    expect(shortcutPathAlias('/write-post'), CreatePostRoute.path);
    expect(shortcutPathAlias('/promo-code'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/mtproto-proxy'), SettingsRoute.path);
    expect(shortcutPathAlias('/socks5'), SettingsRoute.path);
    expect(shortcutPathAlias('/authorizations'), AccountSecurityRoute.path);
    expect(shortcutPathAlias('/email-verify'), VerifyEmailRoute.path);
    expect(shortcutPathAlias('/restore-account'), ForgotPasswordRoute.path);
    expect(
      leftoverPathAlias('/go/open-post/28'),
      '/post/28',
    );
    expect(
      leftoverPathAlias('/go/call-log'),
      ChatsRoute.path,
    );
    expect(shortcutPathAlias('/reels'), isNull);
    expect(shortcutPathAlias('/watch'), isNull);
    expect(resourcePathAlias('/app/5'), isNull);
    expect(resourcePathAlias('/open-media/28'), '/post/28');
    expect(resourcePathAlias('/goto-chat/21'), '/chats/thread/21');
    expect(resourcePathAlias('/goto-channel/1'), '/channel/1');
    expect(resourcePathAlias('/userid/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/add-bot/5'), '/bots/5');
    expect(resourcePathAlias('/appid/5'), '/webapp/5');
    expect(resourcePathAlias('/invid/9'), '/paid/invoices/9');
    expect(resourcePathAlias('/c/1/mute'), '/channel/1');
    expect(resourcePathAlias('/p/28/react'), '/post/28');
    expect(resourcePathAlias('/post/28/react'), '/post/28');
    expect(shortcutPathAlias('/call-history'), ChatsRoute.path);
    expect(shortcutPathAlias('/missed-calls'), ChatsRoute.path);
    expect(shortcutPathAlias('/chat-archive'), ChatArchivedRoute.path);
    expect(shortcutPathAlias('/qr-code'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/lite'), SettingsRoute.path);
    expect(shortcutPathAlias('/send-gift'), StarGiftsInventoryRoute.path);
    expect(shortcutPathAlias('/add-bot'), MyBotsRoute.path);
    expect(shortcutPathAlias('/add-channel'), CreateChannelRoute.path);
    expect(shortcutPathAlias('/cashout'), CreatorRevenueRoute.path);
    expect(shortcutPathAlias('/redeem'), StarsWalletRoute.path);
    expect(shortcutPathAlias('/scheduled-messages'), ScheduledPostsRoute.path);
    expect(shortcutPathAlias('/auction'), StarGiftsMarketplaceRoute.path);
    expect(shortcutPathAlias('/boost-channel'), AdsHubRoute.path);
    expect(shortcutPathAlias('/partner-payout'), PartnerProgramRoute.path);
    expect(shortcutPathAlias('/web-apps'), MiniAppsRoute.path);
    expect(shortcutPathAlias('/filters'), ChatFolderNewRoute.path);
    expect(shortcutPathAlias('/blocked-contacts'), BlockedUsersRoute.path);
    expect(
      leftoverPathAlias('/go/call-history'),
      ChatsRoute.path,
    );
    expect(
      leftoverPathAlias('/go/goto-chat/21'),
      '/chats/thread/21',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/open-media/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/call-history'),
      ChatsRoute.path,
    );
    expect(shortcutPathAlias('/logout'), isNull);
    expect(shortcutPathAlias('/delete-account'), isNull);
    expect(resourcePathAlias('/show-media/28'), '/post/28');
    expect(resourcePathAlias('/chat-id/21'), '/chats/thread/21');
    expect(resourcePathAlias('/channel-id/1'), '/channel/1');
    expect(resourcePathAlias('/user-id/11'), '${ProfileRoute.path}?userId=11');
    expect(resourcePathAlias('/bot-id/5'), '/bots/5');
    expect(resourcePathAlias('/reelid/28'), '/reel/28');
    expect(resourcePathAlias('/goto-msg/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/jump-msg/21/456'), '/chats/thread/21?msg=456');
    expect(resourcePathAlias('/chat/21/archive'), '/chats/thread/21');
    expect(resourcePathAlias('/dm/21/ttl'), '/chats/thread/21');
    expect(resourcePathAlias('/c/1/unmute'), '/channel/1');
    expect(shortcutPathAlias('/phone-calls'), ChatsRoute.path);
    expect(shortcutPathAlias('/starred-messages'), ProfileTabRoute.path);
    expect(shortcutPathAlias('/create-poll'), CreatePostRoute.path);
    expect(shortcutPathAlias('/help-center'), SupportContactRoute.path);
    expect(shortcutPathAlias('/block-user'), BlockedUsersRoute.path);
    expect(shortcutPathAlias('/create-folder'), ChatFolderNewRoute.path);
    expect(shortcutPathAlias('/mute-all'), NotificationSettingsRoute.path);
    expect(shortcutPathAlias('/about-us'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/callhistory'), ChatsRoute.path);
    expect(shortcutPathAlias('/addbot'), MyBotsRoute.path);
    expect(shortcutPathAlias('/joinchannel'), ChannelsManagementRoute.path);
    expect(shortcutPathAlias('/sendgift'), StarGiftsInventoryRoute.path);
    expect(shortcutPathAlias('/delete-chat'), ChatsRoute.path);
    expect(
      leftoverPathAlias('/go/goto-msg/21/456'),
      '/chats/thread/21?msg=456',
    );
    expect(
      leftoverPathAlias('/go/phone-calls'),
      ChatsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/show-media/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/help-center'),
      SupportContactRoute.path,
    );
    expect(
      leftoverPathAlias('/go/openpost/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/openchat/21'),
      '/chats/thread/21',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/react/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/gift-premium'),
      FlexSubscriptionRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/chat/21/media'),
      '/chats/thread/21/media',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/video/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/c/1/info'),
      '/channel/1/info',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/p/28/comments'),
      '/post/28/comments',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/b/5/commands'),
      '/bots/5/commands',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/direct/21'),
      '/chats/thread/21',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/c/1/giveaways'),
      '/channels/1/giveaways',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/c/1/post/28'),
      '/channel/1/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/c/1/28'),
      '/channel/1/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/channel/1/post/28/comments'),
      '/post/28/comments',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/dialogs'),
      ChatsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/go/c/1/info'),
      '/channel/1/info',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/open/chats/21/456'),
      '/chats/thread/21?msg=456',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/share/post/28'),
      '/post/28',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/studio'),
      CreatorToolsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/saved-posts'),
      SavedPostsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/bookmarks'),
      SavedPostsRoute.path,
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/stories/9'),
      '/stories/9',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/donate?to=11'),
      '/donate?to=11',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/addstickers/cute'),
      '/addstickers/cute',
    );
    expect(
      parseDeepLinkToGoPath('https://haneat.app/stickers/4'),
      '/stickers/4',
    );
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
