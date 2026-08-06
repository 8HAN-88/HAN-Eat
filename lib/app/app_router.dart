import 'guest_routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app/kitchen_removed_notice.dart';

import '../screens/post_by_id_screen.dart';
import '../features/navigation/presentation/root_shell.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/profile_auth_screen.dart';
import '../features/settings/presentation/subscription_screen.dart';
import '../features/settings/presentation/stars_wallet_screen.dart';
import '../features/settings/presentation/star_gifts_inventory_screen.dart';
import '../features/settings/presentation/star_invoice_pay_screen.dart';
import '../features/settings/presentation/creator_revenue_screen.dart';
import '../features/channels/presentation/channel_giveaways_screen.dart';
import '../features/settings/presentation/stars_checkout_result_screen.dart';
import '../features/settings/presentation/subscription_success_screen.dart';
import '../features/settings/presentation/subscription_cancel_screen.dart';
import '../features/settings/presentation/support_security_screen.dart';
import '../features/settings/backup_page.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/auth/presentation/two_factor_verify_screen.dart';
import '../features/legal/presentation/legal_consent_screen.dart';
import '../features/auth/presentation/confirm_email_change_screen.dart';
import '../features/settings/presentation/account_security_screen.dart';
import '../features/settings/presentation/two_factor_setup_screen.dart';
import '../features/settings/presentation/close_friends_screen.dart';
import '../features/posts/presentation/create_post_screen.dart';
import '../features/community/presentation/community_upload_screen.dart';
import '../features/posts/presentation/edit_profile_post_screen.dart';
import '../models/post_model.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/miniapps/presentation/miniapps_catalog_screen.dart';
import '../features/stories/presentation/stories_hub_screen.dart';
import '../features/profile/presentation/follow_list_screen.dart';
import '../features/feed/presentation/main_feed_screen.dart';
import '../features/comments/presentation/comments_screen.dart';
import '../features/channels/presentation/channel_detail_screen.dart';
import '../features/channels/presentation/channel_info_screen.dart';
import '../features/channels/presentation/channel_subscribers_screen.dart';
import '../features/channels/presentation/channel_post_detail_screen.dart';
import '../features/channels/presentation/channels_management_screen.dart';
import '../features/channels/presentation/create_channel_screen.dart';
import '../features/channels/presentation/create_channel_post_screen.dart';
import '../features/channels/presentation/channel_settings_screen.dart';
import '../features/creator/presentation/scheduled_posts_screen.dart';
import '../features/creator/presentation/promoted_posts_screen.dart';
import '../features/creator/presentation/creator_tools_screen.dart';
import '../features/channels/presentation/channel_management_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/settings/notification_settings_page.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/moderation/presentation/moderation_dashboard_screen.dart';
import '../features/admin/presentation/admin_refund_queue_screen.dart';
import '../features/moderation/presentation/moderation_queue_screen.dart';
import '../features/moderation/presentation/miniapps_moderation_screen.dart';
import '../features/search/application/search_scope.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/reels/presentation/reels_feed_screen.dart';
import '../features/reels/presentation/reels_fullscreen_screen.dart';
import '../features/chat/presentation/chats_hub_screen.dart';
import '../features/chat/presentation/chat_invite_join_screen.dart';
import '../features/chat/presentation/chat_thread_screen.dart';
import '../features/chat/presentation/username_deep_link_screen.dart';
import '../features/bots/presentation/bot_detail_screen.dart';
import '../features/bots/presentation/my_bots_screen.dart';
import '../models/chat_models.dart';
import '../services/auth_service.dart';
import 'app_bootstrap_state.dart';
import 'auth_route_paths.dart';
import 'boot_screen.dart';
import 'bootstrap.dart';
import 'router_keys.dart';
import 'web_session_landing_screen.dart';
import 'invalid_link_screen.dart';
import '../widgets/app_empty_state.dart';

/// Преобразует `haneat://...` или `https://haneat.app/...` в путь для [GoRouter].
String? parseDeepLinkToGoPath(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      if (host == 'haneat.app' || host == 'www.haneat.app') {
        final path = uri.path;
        // https://haneat.app/@username → /u/username
        if (path.startsWith('/@') && path.length > 2) {
          final handle = path.substring(2).split('/').first;
          if (handle.isNotEmpty) {
            return UsernameDeepLinkRoute.pathFor(handle);
          }
        }
        if (path.isNotEmpty && path != '/') {
          final q = uri.query;
          return q.isEmpty ? path : '$path?$q';
        }
        if (uri.queryParameters.containsKey('ref')) {
          final ref = uri.queryParameters['ref'];
          if (ref != null && ref.isNotEmpty) {
            return '${RegisterRoute.path}?ref=${Uri.encodeComponent(ref)}';
          }
        }
      }
      return null;
    }
    if (uri.scheme != 'haneat') return null;
    if ((uri.host == 'post' || uri.host == 'reel') &&
        uri.pathSegments.isNotEmpty) {
      return '/post/${uri.pathSegments.first}';
    }
    if (uri.host == 'channel' && uri.pathSegments.isNotEmpty) {
      return '/channel/${uri.pathSegments.first}';
    }
    if (uri.host == 'chat' && uri.pathSegments.isNotEmpty) {
      final chatPath = '/chats/thread/${uri.pathSegments.first}';
      final msg = uri.queryParameters['msg'];
      if (msg != null && msg.isNotEmpty) {
        return '$chatPath?msg=${Uri.encodeComponent(msg)}';
      }
      return chatPath;
    }
    if (uri.host == 'chat-invite' && uri.pathSegments.isNotEmpty) {
      return '/chat-invite/${uri.pathSegments.first}';
    }
    if (uri.host == 'u' && uri.pathSegments.isNotEmpty) {
      return UsernameDeepLinkRoute.pathFor(uri.pathSegments.first);
    }
    if (uri.host == 'subscription') {
      if (uri.pathSegments.contains('success')) {
        return SubscriptionSuccessRoute.path;
      }
      if (uri.pathSegments.contains('cancel')) {
        return SubscriptionCancelRoute.path;
      }
    }
    if (uri.host == 'paid') {
      if (uri.pathSegments.contains('success')) {
        return StarsCheckoutSuccessRoute.path;
      }
      if (uri.pathSegments.contains('cancel')) {
        return StarsCheckoutCancelRoute.path;
      }
      if (uri.pathSegments.contains('wallet')) {
        return StarsWalletRoute.path;
      }
    }
    if (uri.host == 'invite') {
      final ref = uri.queryParameters['ref'];
      if (ref != null && ref.isNotEmpty) {
        return '${RegisterRoute.path}?ref=${Uri.encodeComponent(ref)}';
      }
      return RegisterRoute.path;
    }
    if (uri.host == 'auth' && uri.pathSegments.isNotEmpty) {
      final action = uri.pathSegments.first;
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        final encoded = Uri.encodeComponent(token);
        switch (action) {
          case 'verify-email':
            return '${VerifyEmailRoute.path}?token=$encoded';
          case 'reset-password':
            return '${ResetPasswordRoute.path}?token=$encoded';
          case 'confirm-email-change':
            return '${ConfirmEmailChangeRoute.path}?token=$encoded';
        }
      }
    }
  } catch (_) {}
  return null;
}

/// После смены числа вкладок (5→4) старый shell index мог быть вне диапазона → краш IndexedStack.
Widget _safeShellIndexedStack(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) {
  // Empty children during a GoRouter shell remount must NOT be SizedBox.shrink:
  // on Flutter web/CanvasKit that paints as a blank white frame.
  if (children.isEmpty) {
    return const ColoredBox(
      color: Color(0xFF0F1319),
      child: SizedBox.expand(),
    );
  }
  final last = children.length - 1;
  final raw = shell.currentIndex;
  final idx = raw < 0 || raw > last ? 0 : raw;
  return IndexedStack(
    index: idx,
    sizing: StackFit.expand,
    children: List.generate(children.length, (i) {
      return TickerMode(
        enabled: i == idx,
        child: children[i],
      );
    }),
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final homePath =
      FeedRoute.path;
  // Use the real authenticated home (shell). Temporary /web-session landing
  // and hard reloads after login caused blank Safari pages, not stability.
  final stableHomePath = homePath;
  final initialLoc = () {
    if (initialDeepLink != null) {
      final path = parseDeepLinkToGoPath(initialDeepLink!);
      initialDeepLink = null;
      if (path != null) return path;
    }
    if (kIsWeb) {
      final fromBrowser = parseDeepLinkToGoPath(Uri.base.toString());
      if (fromBrowser != null) return fromBrowser;
      // Сессия уже восстановлена в StartupShell — не мигаем /boot.
      return AuthService.instance.currentUser == null
          ? LoginRoute.path
          : stableHomePath;
    }
    return BootScreen.path;
  }();
  return GoRouter(
    navigatorKey: hanEatRootNavigatorKey,
    initialLocation: initialLoc,
    refreshListenable: Listenable.merge([
      AuthService.sessionRevision,
      AppBootstrapState.authReady,
    ]),
    redirect: (context, state) {
      try {
        final loc = state.matchedLocation;
        if (!AppBootstrapState.authReady.value) {
          if (loc == BootScreen.path) return null;
          return BootScreen.path;
        }
        if (loc == BootScreen.path) {
          if (AuthService.instance.currentUser == null) {
            return LoginRoute.path;
          }
          return stableHomePath;
        }
        if (loc == ChannelsListRoute.path) {
          return ChatsRoute.path;
        }
        // Legacy kitchen deep links → feed (+ one-shot notice)
        if (_isRetiredKitchenPath(loc)) {
          KitchenRemovedNotice.markPending();
          return FeedRoute.path;
        }
        final user = AuthService.instance.currentUser;
        final isAuth = user != null;
        if (isAuth &&
            !user.emailVerified &&
            loc != VerifyEmailRoute.path &&
            !loc.startsWith('${VerifyEmailRoute.path}?')) {
          final email = Uri.encodeComponent(user.email);
          return '${VerifyEmailRoute.path}?email=$email';
        }
        if (isAuth &&
            user.legalConsentRequired &&
            loc != LegalConsentRoute.path &&
            !loc.startsWith('${LegalConsentRoute.path}?')) {
          final from = Uri.encodeComponent(state.uri.toString());
          return '${LegalConsentRoute.path}?from=$from';
        }
        if (isAuth &&
            user.emailVerified &&
            (loc == LoginRoute.path || loc == RegisterRoute.path)) {
          return stableHomePath;
        }
        if (isAuth) return null;
        final locBase = loc.split('?').first;
        if (locBase == ProfileAuthRoute.path || locBase == SettingsRoute.path) {
          return LoginRoute.path;
        }
        if (routeAllowsGuestAccess(loc)) return null;
        final isAuthRoute = loc == LoginRoute.path ||
            loc == RegisterRoute.path ||
            loc == '/invite' ||
            loc.startsWith(ChatInviteJoinRoute.basePath) ||
            loc == ForgotPasswordRoute.path ||
            loc == ResetPasswordRoute.path ||
            loc.startsWith(VerifyEmailRoute.path) ||
            loc.startsWith(ConfirmEmailChangeRoute.path) ||
            loc == TwoFactorVerifyRoute.path ||
            loc.startsWith('${TwoFactorVerifyRoute.path}?');
        if (isAuthRoute) return null;
        return LoginRoute.path;
      } catch (e, st) {
        debugPrint('router.redirect recover: $e\n$st');
        return AuthService.instance.currentUser == null
            ? LoginRoute.path
            : stableHomePath;
      }
    },
    routes: [
      GoRoute(
        path: BootScreen.path,
        name: 'boot',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('boot'),
          child: BootScreen(),
        ),
      ),
      if (kIsWeb)
        GoRoute(
          path: WebSocialHomeRoute.path,
          name: WebSocialHomeRoute.name,
          pageBuilder: (context, state) => const MaterialPage(
            child: ChatsHubScreen(),
          ),
        ),
      if (kIsWeb)
        GoRoute(
          path: WebSessionLandingRoute.path,
          name: WebSessionLandingRoute.name,
          pageBuilder: (context, state) => const MaterialPage(
            child: WebSessionLandingScreen(),
          ),
        ),
      StatefulShellRoute(
        navigatorContainerBuilder: _safeShellIndexedStack,
        builder: (context, state, navigationShell) =>
            RootShell(navigationShell: navigationShell),
        branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: FeedRoute.path,
                      name: FeedRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('feed_branch'),
                        child: const MainFeedScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: ChatsRoute.path,
                      name: ChatsRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('chats_branch'),
                        child: const ChatsHubScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: MiniAppsRoute.path,
                      name: MiniAppsRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('mini_apps_branch'),
                        child: const MiniAppsCatalogScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: ProfileTabRoute.path,
                      name: ProfileTabRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('profile_branch'),
                        child: const ProfileScreen(),
                      ),
                    ),
                  ],
                ),
              ],
      ),
      GoRoute(
        path: StoriesRoute.path,
        name: StoriesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StoriesHubScreen()),
      ),
      GoRoute(
        path: ChannelsListRoute.path,
        name: ChannelsListRoute.name,
        redirect: (context, state) => ChatsRoute.path,
      ),
      GoRoute(
        path: SettingsRoute.path,
        name: SettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsScreen()),
      ),
      // Маршруты настроек
      GoRoute(
        path: ProfileAuthRoute.path,
        name: ProfileAuthRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ProfileAuthScreen()),
      ),
      GoRoute(
        path: NotificationsRoute.path,
        name: NotificationsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationsScreen()),
      ),
      GoRoute(
        path: NotificationSettingsRoute.path,
        name: NotificationSettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationSettingsPage()),
      ),
      GoRoute(
        path: CreatorToolsRoute.path,
        name: CreatorToolsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatorToolsScreen()),
      ),
      GoRoute(
        path: ScheduledPostsRoute.path,
        name: ScheduledPostsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ScheduledPostsScreen()),
      ),
      GoRoute(
        path: PromotedPostsRoute.path,
        name: PromotedPostsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: PromotedPostsScreen()),
      ),
      GoRoute(
        path: SubscriptionRoute.path,
        name: SubscriptionRoute.name,
        pageBuilder: (context, state) {
          final product = state.uri.queryParameters['product'];
          return MaterialPage(
            child: SubscriptionScreen(initialProduct: product),
          );
        },
      ),
      GoRoute(
        path: StarsWalletRoute.path,
        name: StarsWalletRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsWalletScreen()),
      ),
      GoRoute(
        path: StarGiftsInventoryRoute.path,
        name: StarGiftsInventoryRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarGiftsInventoryScreen()),
      ),
      GoRoute(
        path: StarInvoicePayRoute.path,
        name: StarInvoicePayRoute.name,
        pageBuilder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['invoiceId'] ?? '') ?? 0;
          return MaterialPage(child: StarInvoicePayScreen(invoiceId: id));
        },
      ),
      GoRoute(
        path: ChannelGiveawaysRoute.path,
        name: ChannelGiveawaysRoute.name,
        pageBuilder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['channelId'] ?? '') ?? 0;
          final name = state.uri.queryParameters['name'] ?? 'Канал';
          final manage = state.uri.queryParameters['manage'] == '1';
          return MaterialPage(
            child: ChannelGiveawaysScreen(
              channelId: id,
              channelName: name,
              canManage: manage,
            ),
          );
        },
      ),
      GoRoute(
        path: StarsCheckoutSuccessRoute.path,
        name: StarsCheckoutSuccessRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsCheckoutSuccessScreen()),
      ),
      GoRoute(
        path: StarsCheckoutCancelRoute.path,
        name: StarsCheckoutCancelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsCheckoutCancelScreen()),
      ),
      GoRoute(
        path: CreatorRevenueRoute.path,
        name: CreatorRevenueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatorRevenueScreen()),
      ),
      GoRoute(
        path: MyBotsRoute.path,
        name: MyBotsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MyBotsScreen()),
      ),
      GoRoute(
        path: BotDetailRoute.path,
        name: BotDetailRoute.name,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['botId'] ?? '') ?? 0;
          final username = state.uri.queryParameters['u'] ?? 'bot';
          final sectionRaw =
              (state.uri.queryParameters['section'] ?? '').toLowerCase();
          final section = switch (sectionRaw) {
            'miniapps' || 'mini_apps' || 'apps' =>
              BotDetailOpenSection.miniApps,
            'newapp' || 'new_app' => BotDetailOpenSection.newApp,
            'commands' => BotDetailOpenSection.commands,
            'token' => BotDetailOpenSection.token,
            _ => BotDetailOpenSection.none,
          };
          return MaterialPage(
            child: BotDetailScreen(
              botId: id,
              botUsername: username,
              openSection: section,
            ),
          );
        },
      ),
      GoRoute(
        path: SubscriptionSuccessRoute.path,
        name: SubscriptionSuccessRoute.name,
        pageBuilder: (context, state) {
          final sessionId = state.uri.queryParameters['session_id'];
          return MaterialPage(
            child: SubscriptionSuccessScreen(sessionId: sessionId),
          );
        },
      ),
      GoRoute(
        path: SubscriptionCancelRoute.path,
        name: SubscriptionCancelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SubscriptionCancelScreen()),
      ),
      GoRoute(
        path: SupportSecurityRoute.path,
        name: SupportSecurityRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SupportSecurityScreen()),
      ),
      GoRoute(
        path: BackupRoute.path,
        name: BackupRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: BackupPage()),
      ),
      // Auth маршруты
      GoRoute(
        path: '/invite',
        name: 'invite',
        redirect: (context, state) {
          final ref = state.uri.queryParameters['ref'];
          if (ref != null && ref.isNotEmpty) {
            return '${RegisterRoute.path}?ref=${Uri.encodeComponent(ref)}';
          }
          return RegisterRoute.path;
        },
      ),
      GoRoute(
        path: ChatInviteJoinRoute.path,
        name: ChatInviteJoinRoute.name,
        pageBuilder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return MaterialPage(
            child: ChatInviteJoinScreen(token: token),
          );
        },
      ),
      GoRoute(
        path: UsernameDeepLinkRoute.path,
        name: UsernameDeepLinkRoute.name,
        pageBuilder: (context, state) {
          final username = state.pathParameters['username'] ?? '';
          return MaterialPage(
            child: UsernameDeepLinkScreen(username: username),
          );
        },
      ),
      GoRoute(
        path: LoginRoute.path,
        name: LoginRoute.name,
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('login'),
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: RegisterRoute.path,
        name: RegisterRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: RegisterScreen()),
      ),
      GoRoute(
        path: LegalConsentRoute.path,
        name: LegalConsentRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: LegalConsentScreen()),
      ),
      GoRoute(
        path: ForgotPasswordRoute.path,
        name: ForgotPasswordRoute.name,
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return MaterialPage(
            child: ForgotPasswordScreen(initialEmail: email),
          );
        },
      ),
      GoRoute(
        path: ResetPasswordRoute.path,
        name: ResetPasswordRoute.name,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'];
          return MaterialPage(
            child: ResetPasswordScreen(initialToken: token),
          );
        },
      ),
      GoRoute(
        path: VerifyEmailRoute.path,
        name: VerifyEmailRoute.name,
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          final token = state.uri.queryParameters['token'];
          return MaterialPage(
            child: VerifyEmailScreen(email: email, initialToken: token),
          );
        },
      ),
      GoRoute(
        path: TwoFactorVerifyRoute.path,
        name: TwoFactorVerifyRoute.name,
        pageBuilder: (context, state) {
          final extra = state.extra;
          String pending = '';
          String? email;
          if (extra is Map) {
            pending = extra['pendingToken'] as String? ?? '';
            email = extra['email'] as String?;
          }
          if (pending.isEmpty) {
            return const MaterialPage(child: LoginScreen());
          }
          return MaterialPage(
            child: TwoFactorVerifyScreen(
              pendingToken: pending,
              email: email,
            ),
          );
        },
      ),
      GoRoute(
        path: ConfirmEmailChangeRoute.path,
        name: ConfirmEmailChangeRoute.name,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return MaterialPage(
            child: ConfirmEmailChangeScreen(token: token),
          );
        },
      ),
      GoRoute(
        path: AccountSecurityRoute.path,
        name: AccountSecurityRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AccountSecurityScreen()),
      ),
      GoRoute(
        path: TwoFactorSetupRoute.path,
        name: TwoFactorSetupRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: TwoFactorSetupScreen()),
      ),
      GoRoute(
        path: CloseFriendsRoute.path,
        name: CloseFriendsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CloseFriendsScreen()),
      ),
      // Profile
      GoRoute(
        path: ProfileRoute.path,
        name: ProfileRoute.name,
        pageBuilder: (context, state) {
          final userId = state.uri.queryParameters['userId'];
          return MaterialPage(
            child: ProfileScreen(
              userId: userId != null ? int.tryParse(userId) : null,
            ),
          );
        },
      ),
      GoRoute(
        path: ProfileFollowersRoute.path,
        name: ProfileFollowersRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.uri.queryParameters['userId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписчики'),
            );
          }
          return MaterialPage(
            child: FollowListScreen(userId: id, type: FollowListType.followers),
          );
        },
      ),
      GoRoute(
        path: ProfileFollowingRoute.path,
        name: ProfileFollowingRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.uri.queryParameters['userId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписки'),
            );
          }
          return MaterialPage(
            child: FollowListScreen(userId: id, type: FollowListType.following),
          );
        },
      ),
      // Create Post
      GoRoute(
        path: CreatePostRoute.path,
        name: CreatePostRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatePostScreen()),
      ),
            GoRoute(
        path: CreateReelRoute.path,
        name: CreateReelRoute.name,
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.uri.queryParameters['channelId']);
          final channelName = state.uri.queryParameters['channelName'];
          return MaterialPage(
            child: CommunityUploadScreen(
              channelId: channelId,
              channelName: channelName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/post/:postId/edit',
        name: 'edit_profile_post',
        pageBuilder: (context, state) {
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост'),
            );
          }
          return MaterialPage(
            child: EditProfilePostScreen(postId: postId),
          );
        },
      ),
      // Comments
      GoRoute(
        path: '/post/:postId/comments',
        name: 'post_comments',
        pageBuilder: (context, state) {
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Комментарии'),
            );
          }
          return MaterialPage(child: CommentsScreen(postId: postId));
        },
      ),
      GoRoute(
        path: '/post/:postId',
        name: 'post_by_id',
        pageBuilder: (context, state) {
          final postId = int.tryParse(state.pathParameters['postId'] ?? '');
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост'),
            );
          }
          return MaterialPage(child: PostByIdScreen(postId: postId));
        },
      ),
      // Channels
      GoRoute(
        path: '/channel/:channelId',
        name: 'channel_page',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          return MaterialPage(child: ChannelDetailScreen(channelId: channelId));
        },
      ),
      GoRoute(
        path: '/channel/:channelId/info',
        name: 'channel_info',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          return MaterialPage<void>(
            child: ChannelInfoScreen(channelId: channelId),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/subscribers',
        name: 'channel_subscribers',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписчики канала'),
            );
          }
          return MaterialPage<void>(
            child: ChannelSubscribersScreen(
              channelId: channelId,
              channelName: state.uri.queryParameters['channelName'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/post/:postId',
        name: 'channel_post_detail',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (channelId == null || postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост канала'),
            );
          }
          return MaterialPage(
            child: ChannelPostDetailScreen(
              channelId: channelId,
              postId: postId,
            ),
          );
        },
      ),
      GoRoute(
        path: ChannelsManagementRoute.path,
        name: ChannelsManagementRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ChannelsManagementScreen()),
      ),
      GoRoute(
        path: CreateChannelRoute.path,
        name: CreateChannelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreateChannelScreen()),
      ),
            GoRoute(
        path: '/channel/:channelId/create-post',
        name: 'create_channel_post',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          final postType = state.uri.queryParameters['type'] ?? 'text';
          return MaterialPage(
            child: CreateChannelPostScreen(
              channelId: channelId,
              postType: postType,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/post/:postId/edit',
        name: 'edit_channel_post',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (channelId == null || postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Редактирование поста'),
            );
          }
          final extra = state.extra;
          final Map<String, dynamic>? postData = extra is Map<String, dynamic>
              ? extra
              : extra is PostModel
                  ? extra.toJson()
                  : null;
          return MaterialPage(
            child: CreateChannelPostScreen(
              channelId: channelId,
              postId: postId,
              postData: postData,
              postType: postData?['type'] ?? 'text',
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/settings',
        name: 'channel_settings',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Настройки канала'),
            );
          }
          final channelName =
              state.uri.queryParameters['channelName'] ?? 'канал';
          return MaterialPage(
            child: ChannelSettingsScreen(
              channelId: channelId,
              channelName: channelName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/management',
        name: 'channel_management',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Управление каналом'),
            );
          }
          return MaterialPage(
            child: ChannelManagementScreen(channelId: channelId),
          );
        },
      ),
      // Notifications List (удален дубликат - используется NotificationsRoute выше)
      // Support
      GoRoute(
        path: SupportContactRoute.path,
        name: SupportContactRoute.name,
        pageBuilder: (context, state) {
          final subject = state.uri.queryParameters['subject'];
          final message = state.uri.queryParameters['message'];
          final type = state.uri.queryParameters['type'];
          return MaterialPage<void>(
            child: SupportScreen(
              initialSubject: subject,
              initialMessage: message,
              initialType: type,
            ),
          );
        },
      ),
      // Analytics
      GoRoute(
        path: AppAnalyticsRoute.path,
        name: AppAnalyticsRoute.name,
        pageBuilder: (context, state) {
          final postId = state.uri.queryParameters['postId'];
          return MaterialPage(
            child: AnalyticsScreen(
              postId: postId != null ? int.tryParse(postId) : null,
            ),
          );
        },
      ),
      // Moderation
      GoRoute(
        path: ModerationDashboardRoute.path,
        name: ModerationDashboardRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ModerationDashboardScreen()),
      ),
      GoRoute(
        path: ModerationQueueRoute.path,
        name: ModerationQueueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ModerationQueueScreen()),
      ),
      GoRoute(
        path: MiniAppsModerationRoute.path,
        name: MiniAppsModerationRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MiniAppsModerationScreen()),
      ),
      GoRoute(
        path: AdminRefundQueueRoute.path,
        name: AdminRefundQueueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminRefundQueueScreen()),
      ),
      // Легаси: /community → главная лента; избранное — отдельный маршрут
      GoRoute(
        path: CommunityRoute.path,
        name: CommunityRoute.name,
        redirect: (context, state) => FeedRoute.path,
      ),
            GoRoute(
        path: UserSearchRoute.path,
        name: UserSearchRoute.name,
        // Legacy alias — same UI as SearchRoute.
        redirect: (context, state) => SearchRoute.path,
      ),
      GoRoute(
        path: '${ChatThreadRoute.path}/:conversationId',
        name: ChatThreadRoute.name,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['conversationId'] ?? '');
          final extra = state.extra;
          final openArgs = extra is ChatThreadOpenArgs ? extra : null;
          final initialConversation = openArgs?.conversation ??
              (extra is ChatConversation ? extra : null);
          final initialPeer =
              openArgs?.peer ?? (extra is ChatUserBrief ? extra : null);
          if (id == null) {
            return const MaterialPage(
              child: AppEmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'Чат не найден',
              ),
            );
          }
          final msgParam = state.uri.queryParameters['msg'];
          final jumpFromQuery = int.tryParse(msgParam ?? '');
          return MaterialPage(
            child: ChatThreadLoaderScreen(
              conversationId: id,
              initialConversation: initialConversation,
              initialPeer: initialPeer,
              initialJumpMessageId:
                  openArgs?.jumpToMessageId ?? jumpFromQuery,
              initialDraftText: openArgs?.initialDraftText,
            ),
          );
        },
      ),
      // Search
      GoRoute(
        path: SearchRoute.path,
        name: SearchRoute.name,
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return MaterialPage<void>(
            child: SearchScreen(
              initialQuery: params['q'],
              scope: searchScopeFromQuery(params['scope']),
              feedType: params['feed_type'],
              followingOnly: params['following'] == '1',
            ),
          );
        },
      ),
      // Reels Feed
      GoRoute(
        path: ReelsRoute.path,
        name: ReelsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ReelsFeedScreen()),
      ),
      // Reels Fullscreen (при тапе на видео в ленте — поверх shell, без нижней панели)
      GoRoute(
        path: ReelsFullscreenRoute.path,
        name: ReelsFullscreenRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is! PostModel) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Рилс'),
            );
          }
          return MaterialPage(
            child: ReelsFullscreenScreen(initialPost: extra),
          );
        },
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage(
      child: _RouterRecoveryScreen(error: state.error),
    ),
  );
});

class _RouterRecoveryScreen extends StatefulWidget {
  const _RouterRecoveryScreen({this.error});

  final Object? error;

  @override
  State<_RouterRecoveryScreen> createState() => _RouterRecoveryScreenState();
}

class _RouterRecoveryScreenState extends State<_RouterRecoveryScreen> {
  bool _redirected = false;
  bool _redirectedSecondPass = false;
  bool _forcedLogout = false;

  String get _stableHomePath =>
      FeedRoute.path;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _redirected) return;
      _redirected = true;
      final user = AuthService.instance.currentUser;
      context.go(user == null ? LoginRoute.path : _stableHomePath);
    });
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted || !_redirected || _redirectedSecondPass) return;
      _redirectedSecondPass = true;
      final user = AuthService.instance.currentUser;
      context.go(user == null ? LoginRoute.path : _stableHomePath);
    });
    Future<void>.delayed(const Duration(seconds: 12), () async {
      if (!mounted || _forcedLogout) return;
      // Last-resort recovery: if this screen still exists after two redirects,
      // reset session and force a clean login path.
      _forcedLogout = true;
      await AuthService.logout();
      if (!mounted) return;
      context.go(LoginRoute.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1319),
      appBar: AppBar(
        title: const Text('Восстановление'),
        backgroundColor: Colors.transparent,
      ),
      body: AppEmptyState(
        icon: Icons.sync_problem_rounded,
        title: 'Восстанавливаем экран',
        subtitle: kDebugMode
            ? '${widget.error}'
            : 'Обнаружена ошибка маршрута. Выполняем автоматический возврат.',
        action: FilledButton(
          onPressed: () {
            final user = AuthService.instance.currentUser;
            context.go(user == null ? LoginRoute.path : _stableHomePath);
          },
          child: const Text('Продолжить'),
        ),
      ),
    );
  }
}


class CommunityRoute {
  static const path = '/community';
  static const name = 'community';
}

class ModerationDashboardRoute {
  static const path = '/moderation-dashboard';
  static const name = 'moderation_dashboard';
}

class ModerationQueueRoute {
  static const path = '/moderation';
  static const name = 'moderation';
}

class MiniAppsModerationRoute {
  static const path = '/moderation/miniapps';
  static const name = 'moderation_miniapps';
}

class AdminRefundQueueRoute {
  static const path = '/admin/refunds';
  static const name = 'admin_refunds';
}


class UserSearchRoute {
  static const path = '/users';
  static const name = 'user_search';
}

class ChannelsListRoute {
  static const path = '/channels';
  static const name = 'channels';
}

class FeedRoute {
  static const path = '/feed';
  static const name = 'feed';
}

class WebSocialHomeRoute {
  static const path = '/web-home';
  static const name = 'web_home';
}

class WebSessionLandingRoute {
  static const path = '/web-session';
  static const name = 'web_session';
}

class ChatsRoute {
  static const path = '/chats';
  static const name = 'chats';
}

class MiniAppsRoute {
  static const path = '/mini-apps';
  static const name = 'mini_apps';
}

class StoriesRoute {
  static const path = '/stories';
  static const name = 'stories';
}

class ChatThreadRoute {
  static const path = '/chats/thread';
  static const name = 'chat_thread';

  static String pathFor(ChatConversation conv) => '$path/${conv.id}';

  static String pathForId(int conversationId) => '$path/$conversationId';
}

class ChatInviteJoinRoute {
  static const path = '/chat-invite/:token';
  static const basePath = '/chat-invite';
  static const name = 'chat_invite_join';
}

class UsernameDeepLinkRoute {
  static const path = '/u/:username';
  static const basePath = '/u';
  static const name = 'username_deep_link';

  static String pathFor(String username) {
    final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
    return '$basePath/${Uri.encodeComponent(handle)}';
  }
}

class ChatThreadOpenArgs {
  const ChatThreadOpenArgs({
    this.conversation,
    this.peer,
    this.jumpToMessageId,
    this.initialDraftText,
  });

  final ChatConversation? conversation;
  final ChatUserBrief? peer;
  final int? jumpToMessageId;
  final String? initialDraftText;
}

/// Вкладка «Профиль» в нижней навигации (хаб, не путать с [ProfileRoute] ленты профиля).
class ProfileTabRoute {
  static const path = '/me';
  static const name = 'profile_tab';
}


bool _isRetiredKitchenPath(String loc) {
  if (loc == MenuRoute.path ||
      loc == CreateRecipeRoute.path ||
      loc == '/create-recipe' ||
      loc == '/meal-plan' ||
      loc.startsWith('/meal-plan/') ||
      loc == '/shopping' ||
      loc == '/shopping-list' ||
      loc == '/shopping-import' ||
      loc == '/categories' ||
      loc == '/allergies' ||
      loc == '/diet' ||
      loc == '/diet-allergies' ||
      loc == '/favorites' ||
      loc == '/scan-result' ||
      loc == '/cooking-mode' ||
      loc.startsWith('/recipe/')) {
    return true;
  }
  return loc.startsWith('/channel/') && loc.contains('/create-recipe');
}

/// Legacy kitchen paths (redirect to feed).
class MenuRoute {
  static const path = '/menu';
}

class CreateRecipeRoute {
  static const path = '/create-recipe';
}

class SettingsRoute {
  static const path = '/settings';
  static const name = 'settings';
}









class ProfileAuthRoute {
  static const path = '/profile-auth';
  static const name = 'profile_auth';
}





class NotificationsRoute {
  static const path = '/notifications';
  static const name = 'notifications';
}

class NotificationSettingsRoute {
  static const path = '/settings/notifications';
  static const name = 'notification_settings';
}

class CreatorToolsRoute {
  static const path = '/creator/tools';
  static const name = 'creator_tools';
}

class ScheduledPostsRoute {
  static const path = '/creator/scheduled-posts';
  static const name = 'scheduled_posts';
}

class PromotedPostsRoute {
  static const path = '/creator/promoted-posts';
  static const name = 'promoted_posts';
}

class SubscriptionRoute {
  static const path = '/subscription';
  static const name = 'subscription';

  static String pathWithProduct(String product) =>
      '$path?product=${Uri.encodeComponent(product)}';
}

class StarsWalletRoute {
  static const path = '/paid/wallet';
  static const name = 'stars_wallet';
}

class StarGiftsInventoryRoute {
  static const path = '/paid/gifts';
  static const name = 'star_gifts_inventory';
}

class StarInvoicePayRoute {
  static const path = '/paid/invoices/:invoiceId';
  static const name = 'star_invoice_pay';

  static String pathFor(int invoiceId) => '/paid/invoices/$invoiceId';
}

class ChannelGiveawaysRoute {
  static const path = '/channels/:channelId/giveaways';
  static const name = 'channel_giveaways';

  static String pathFor(
    int channelId, {
    String? name,
    bool canManage = false,
  }) {
    final params = <String, String>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (canManage) 'manage': '1',
    };
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return '/channels/$channelId/giveaways$q';
  }
}

class StarsCheckoutSuccessRoute {
  static const path = '/paid/success';
  static const name = 'stars_checkout_success';
}

class StarsCheckoutCancelRoute {
  static const path = '/paid/cancel';
  static const name = 'stars_checkout_cancel';
}

class CreatorRevenueRoute {
  static const path = '/paid/revenue';
  static const name = 'creator_revenue';
}

class MyBotsRoute {
  static const path = '/bots/my';
  static const name = 'my_bots';
}

class BotDetailRoute {
  static const path = '/bots/:botId';
  static const name = 'bot_detail';

  static String pathFor(
    int botId, {
    String? username,
    BotDetailOpenSection section = BotDetailOpenSection.none,
  }) {
    final params = <String, String>{};
    if (username != null && username.trim().isNotEmpty) {
      params['u'] = username.trim();
    }
    switch (section) {
      case BotDetailOpenSection.miniApps:
        params['section'] = 'miniapps';
      case BotDetailOpenSection.newApp:
        params['section'] = 'newapp';
      case BotDetailOpenSection.commands:
        params['section'] = 'commands';
      case BotDetailOpenSection.token:
        params['section'] = 'token';
      case BotDetailOpenSection.none:
        break;
    }
    final uri = Uri(
      path: '/bots/$botId',
      queryParameters: params.isEmpty ? null : params,
    );
    return uri.toString();
  }
}

class SubscriptionSuccessRoute {
  static const path = '/subscription/success';
  static const name = 'subscription_success';
}

class SubscriptionCancelRoute {
  static const path = '/subscription/cancel';
  static const name = 'subscription_cancel';
}

class SupportSecurityRoute {
  static const path = '/support-security';
  static const name = 'support_security';
}

class BackupRoute {
  static const path = '/backup';
  static const name = 'backup';
}

class LoginRoute {
  static const path = AuthPaths.login;
  static const name = 'login';
}

class RegisterRoute {
  static const path = AuthPaths.register;
  static const name = 'register';
}

class LegalConsentRoute {
  static const path = AuthPaths.legalConsent;
  static const name = 'legal_consent';
}

class ForgotPasswordRoute {
  static const path = AuthPaths.forgotPassword;
  static const name = 'forgot_password';

  static String withEmail(String email) =>
      AuthPaths.forgotPasswordWithEmail(email);
}

class ResetPasswordRoute {
  static const path = AuthPaths.resetPassword;
  static const name = 'reset_password';
}

class VerifyEmailRoute {
  static const path = AuthPaths.verifyEmail;
  static const name = 'verify_email';

  static String withEmail(String email) =>
      AuthPaths.verifyEmailWithEmail(email);
}

class TwoFactorVerifyRoute {
  static const path = AuthPaths.twoFactorVerify;
  static const name = 'two_factor_verify';
}

class ConfirmEmailChangeRoute {
  static const path = '/confirm-email-change';
  static const name = 'confirm_email_change';
}

class AccountSecurityRoute {
  static const path = '/account-security';
  static const name = 'account_security';
}

class TwoFactorSetupRoute {
  static const path = '/two-factor-setup';
  static const name = 'two_factor_setup';
}

class CloseFriendsRoute {
  static const path = '/close-friends';
  static const name = 'close_friends';
}

class ProfileRoute {
  static const path = '/profile';
  static const name = 'profile';

  /// Ссылка на экран профиля с [userId] в query (как в GoRoute `/profile`).
  static String withUserId(int userId) => '$path?userId=$userId';
}

class ProfileFollowersRoute {
  static const path = '/profile/followers';
  static const name = 'profile_followers';

  static String withUserId(int userId) => '$path?userId=$userId';
}

class ProfileFollowingRoute {
  static const path = '/profile/following';
  static const name = 'profile_following';

  static String withUserId(int userId) => '$path?userId=$userId';
}

/// Комментарии к посту (совпадает с GoRoute `post_comments`).
class PostCommentsRoute {
  static const name = 'post_comments';

  static String pathFor(int postId) => '/post/$postId/comments';
}

/// Редактирование поста профиля (GoRoute `edit_profile_post`).
class EditProfilePostRoute {
  static const name = 'edit_profile_post';

  static String pathFor(int postId) => '/post/$postId/edit';
}

/// Карточка канала и вложенные пути (совпадают с GoRouter).
class ChannelDetailRoute {
  static String pathFor(int channelId) => '/channel/$channelId';

  static String info(int channelId, {String? channelName}) {
    final base = '${pathFor(channelId)}/info';
    if (channelName == null || channelName.trim().isEmpty) return base;
    return '$base?channelName=${Uri.encodeComponent(channelName)}';
  }

  static String subscribers(int channelId, {String? channelName}) {
    final base = '${pathFor(channelId)}/subscribers';
    if (channelName == null || channelName.trim().isEmpty) return base;
    return '$base?channelName=${Uri.encodeComponent(channelName)}';
  }

  static String management(int channelId) => '${pathFor(channelId)}/management';

  static String settings(int channelId, String channelName) =>
      '${pathFor(channelId)}/settings?channelName=${Uri.encodeComponent(channelName)}';

  /// Query: `type`, опционально `channelName`.
  static String createPost(
    int channelId, {
    String? channelName,
    String type = 'text',
  }) {
    final params = <String, String>{'type': type};
    if (channelName != null && channelName.trim().isNotEmpty) {
      params['channelName'] = channelName.trim();
    }
    final q = Uri(queryParameters: params).query;
    return '${pathFor(channelId)}/create-post${q.isEmpty ? '' : '?$q'}';
  }


  static String post(int channelId, int postId) =>
      '${pathFor(channelId)}/post/$postId';

  static String postEdit(int channelId, int postId) =>
      '${pathFor(channelId)}/post/$postId/edit';
}

/// Пост по id (GoRoute `post_by_id`).
class PostFeedRoute {
  static String pathFor(int postId) => '/post/$postId';
}

/// Экран аналитики (GoRoute `analytics`).
class AppAnalyticsRoute {
  static const path = '/analytics';
  static const name = 'analytics';

  static String pathWithPostId(int postId) => '$path?postId=$postId';
}

/// Создание нового канала.
class CreateChannelRoute {
  static const path = '/create-channel';
  static const name = 'create_channel';
}

/// Каталог каналов, поиск и фильтры.
class ChannelsManagementRoute {
  static const path = '/channels/management';
  static const name = 'channels_management';

  static String pathWithSearch(String query) =>
      '$path?search=${Uri.encodeComponent(query)}';
}

class SupportContactRoute {
  static const path = '/support';
  static const name = 'support';

  static String withSubjectMessage(
    String subject,
    String message, {
    String? type,
  }) {
    final params = <String, String>{
      'subject': subject,
      'message': message,
    };
    if (type != null && type.isNotEmpty) {
      params['type'] = type;
    }
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$path?$query';
  }

  static String bugReport() => withSubjectMessage(
        'Сообщение об ошибке',
        'Опишите ошибку подробно:\n\n'
            '• На каком экране это произошло\n'
            '• Что вы делали перед ошибкой\n'
            '• Что ожидали увидеть',
        type: 'technical_issue',
      );
}

class CreatePostRoute {
  static const path = '/create-post';
  static const name = 'create_post';
}


class CreateReelRoute {
  static const path = '/create-reel';
  static const name = 'create_reel';

  static String uri({int? channelId, String? channelName}) {
    if (channelId == null) return path;
    final params = <String, String>{'channelId': '$channelId'};
    if (channelName != null && channelName.trim().isNotEmpty) {
      params['channelName'] = channelName.trim();
    }
    return '$path?${Uri(queryParameters: params).query}';
  }
}

class SearchRoute {
  static const path = '/search';
  static const name = 'search';

  static String pathFor({
    String? q,
    SearchScope? scope,
    String? feedType,
    bool followingOnly = false,
  }) {
    final params = <String, String>{};
    final query = q?.trim();
    if (query != null && query.isNotEmpty) {
      params['q'] = query;
    }
    if (scope != null) {
      params['scope'] = scope.name;
    }
    // Опционально для прямых ссылок (хештеги и т.п.), не из нижней панели.
    if (feedType != null && feedType != 'all') {
      params['feed_type'] = feedType;
    }
    if (followingOnly) {
      params['following'] = '1';
    }
    if (params.isEmpty) return path;
    return '$path?${Uri(queryParameters: params).query}';
  }
}

class ReelsRoute {
  static const path = '/reels';
  static const name = 'reels';
}

class ReelsFullscreenRoute {
  static const path = '/reels/fullscreen';
  static const name = 'reels_fullscreen';
}
