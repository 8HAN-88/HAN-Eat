import 'guest_routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:typed_data';

import '../features/menu/presentation/menu_screen.dart';
import '../features/menu/presentation/scan_result_screen.dart';
import '../screens/cooking_mode_screen.dart';
import '../screens/recipe_by_id_screen.dart';
import '../screens/post_by_id_screen.dart';
import '../features/shopping/shopping_import_screen.dart';
import '../models/recipe.dart';
import '../features/navigation/presentation/root_shell.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/profile_auth_screen.dart';
import '../features/settings/presentation/allergies_screen.dart';
import '../features/settings/presentation/diet_screen.dart';
import '../features/settings/presentation/subscription_screen.dart';
import '../features/settings/presentation/subscription_success_screen.dart';
import '../features/settings/presentation/subscription_cancel_screen.dart';
import '../features/settings/presentation/support_security_screen.dart';
import '../features/settings/backup_page.dart';
import '../features/meal_plan/presentation/meal_plan_screen.dart';
import '../features/meal_plan/presentation/ai_meal_plan_screen.dart';
import '../features/meal_plan/presentation/meal_plan_analytics_screen.dart';
import '../features/meal_plan/presentation/meal_plan_nutrition_settings_screen.dart';
import '../features/meal_plan/presentation/meal_plan_survey_flow_screen.dart';
import '../features/shopping/shopping_page.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/auth/presentation/confirm_email_change_screen.dart';
import '../features/settings/presentation/account_security_screen.dart';
import '../features/posts/presentation/create_post_screen.dart';
import '../features/posts/presentation/edit_profile_post_screen.dart';
import '../models/post_model.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/feed/presentation/main_feed_screen.dart';
import '../features/comments/presentation/comments_screen.dart';
import '../features/channels/presentation/channels_main_screen.dart';
import '../features/channels/presentation/channel_detail_screen.dart';
import '../features/channels/presentation/channel_info_screen.dart';
import '../features/channels/presentation/channel_post_detail_screen.dart';
import '../features/channels/presentation/channels_management_screen.dart';
import '../features/channels/presentation/create_channel_screen.dart';
import '../features/channels/presentation/create_channel_recipe_screen.dart';
import '../features/channels/presentation/create_channel_post_screen.dart';
import '../features/channels/presentation/channel_settings_screen.dart';
import '../features/creator/presentation/scheduled_posts_screen.dart';
import '../features/creator/presentation/promoted_posts_screen.dart';
import '../features/creator/presentation/creator_tools_screen.dart';
import '../features/channels/presentation/channel_management_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/moderation/presentation/moderation_dashboard_screen.dart';
import '../features/admin/presentation/admin_refund_queue_screen.dart';
import '../features/moderation/presentation/moderation_queue_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/favorites/favorites_page.dart';
import '../features/profile/user_search_page.dart';
import '../features/reels/presentation/reels_feed_screen.dart';
import '../features/reels/presentation/reels_fullscreen_screen.dart';
import '../services/auth_service.dart';
import 'bootstrap.dart';
import 'router_keys.dart';
import 'invalid_link_screen.dart';
import '../widgets/app_empty_state.dart';

/// Преобразует `haneat://...` в путь для [GoRouter].
String? parseDeepLinkToGoPath(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'haneat') return null;
    if (uri.host == 'recipe' && uri.pathSegments.isNotEmpty) {
      return '/recipe/${uri.pathSegments.first}';
    }
    if (uri.host == 'shopping' && uri.pathSegments.contains('import')) {
      final data = uri.queryParameters['data'];
      if (data != null && data.isNotEmpty) {
        return '${ShoppingImportRoute.path}?data=${Uri.encodeComponent(data)}';
      }
    }
    if ((uri.host == 'post' || uri.host == 'reel') &&
        uri.pathSegments.isNotEmpty) {
      return '/post/${uri.pathSegments.first}';
    }
    if (uri.host == 'channel' && uri.pathSegments.isNotEmpty) {
      return '/channel/${uri.pathSegments.first}';
    }
    if (uri.host == 'subscription') {
      if (uri.pathSegments.contains('success')) {
        return SubscriptionSuccessRoute.path;
      }
      if (uri.pathSegments.contains('cancel')) {
        return SubscriptionCancelRoute.path;
      }
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

final appRouterProvider = Provider<GoRouter>((ref) {
  final initialLoc = () {
    if (initialDeepLink != null) {
      final path = parseDeepLinkToGoPath(initialDeepLink!);
      initialDeepLink = null;
      if (path != null) return path;
    }
    if (AuthService.instance.currentUser == null) {
      return LoginRoute.path;
    }
    return FeedRoute.path;
  }();
  return GoRouter(
    navigatorKey: hanEatRootNavigatorKey,
    initialLocation: initialLoc,
    refreshListenable: AuthService.sessionRevision,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/shopping') {
        return ShoppingListRoute.path;
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
      if (isAuth) return null;
      if (routeAllowsGuestAccess(loc)) return null;
      final isAuthRoute = loc == LoginRoute.path ||
          loc == RegisterRoute.path ||
          loc == ProfileAuthRoute.path ||
          loc == ForgotPasswordRoute.path ||
          loc == ResetPasswordRoute.path ||
          loc.startsWith(VerifyEmailRoute.path) ||
          loc.startsWith(ConfirmEmailChangeRoute.path);
      if (isAuthRoute) return null;
      return LoginRoute.path;
    },
    routes: [
      StatefulShellRoute.indexedStack(
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
                path: ChannelsListRoute.path,
                name: ChannelsListRoute.name,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: const ValueKey('channels_branch'),
                  child: const ChannelsMainScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: MenuRoute.path,
                name: MenuRoute.name,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: const ValueKey('menu_branch'),
                  child: const MenuScreen(),
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
        path: SettingsRoute.path,
        name: SettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsScreen()),
      ),
      // Отдельный маршрут для плана питания
      GoRoute(
        path: MealPlanRoute.path,
        name: MealPlanRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MealPlanScreen()),
      ),
      GoRoute(
        path: AiMealPlanRoute.path,
        name: AiMealPlanRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AiMealPlanScreen()),
      ),
      GoRoute(
        path: MealPlanAnalyticsRoute.path,
        name: MealPlanAnalyticsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MealPlanAnalyticsScreen()),
      ),
      GoRoute(
        path: NutritionSurveyRoute.path,
        name: NutritionSurveyRoute.name,
        pageBuilder: (context, state) => MaterialPage(
          child: MealPlanSurveyFlowScreen(
            skipWelcome: state.extra == true,
          ),
        ),
      ),
      GoRoute(
        path: MealPlanNutritionSettingsRoute.path,
        name: MealPlanNutritionSettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MealPlanNutritionSettingsScreen()),
      ),
      // Результат сканирования блюда (фото → питательность и рецепты)
      GoRoute(
        path: ScanResultRoute.path,
        name: ScanResultRoute.name,
        pageBuilder: (context, state) {
          final bytes =
              state.extra is Uint8List ? state.extra as Uint8List : null;
          if (bytes == null) {
            return MaterialPage(
              child: Scaffold(
                appBar: AppBar(title: const Text('Сканирование')),
                body: const Center(
                  child:
                      Text('Нет данных изображения. Сделайте снимок ещё раз.'),
                ),
              ),
            );
          }
          return MaterialPage(child: ScanResultScreen(bytes: bytes));
        },
      ),
      GoRoute(
        path: CookingModeRoute.path,
        name: CookingModeRoute.name,
        pageBuilder: (context, state) {
          final recipe = state.extra is Recipe ? state.extra as Recipe : null;
          if (recipe == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(
                title: 'Режим готовки',
                message: 'Рецепт не передан',
              ),
            );
          }
          return MaterialPage(child: CookingModeScreen(recipe: recipe));
        },
      ),
      GoRoute(
        path: RecipeByIdRoute.path,
        name: RecipeByIdRoute.name,
        pageBuilder: (context, state) {
          final idStr = state.pathParameters['id'];
          final id = int.tryParse(idStr ?? '');
          if (id == null || id < 1) {
            return const MaterialPage(
              child: InvalidLinkScreen(
                title: 'Рецепт',
                message: 'Неверная ссылка на рецепт',
              ),
            );
          }
          return MaterialPage(child: RecipeByIdScreen(recipeId: id));
        },
      ),
      GoRoute(
        path: ShoppingImportRoute.path,
        name: ShoppingImportRoute.name,
        pageBuilder: (context, state) {
          final data = state.uri.queryParameters['data'];
          return MaterialPage(
            child: ShoppingImportScreen(dataBase64: data),
          );
        },
      ),
      // Маршрут для категорий
      GoRoute(
        path: CategoriesRoute.path,
        name: CategoriesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CategoriesScreen()),
      ),
      // Маршруты настроек
      GoRoute(
        path: ProfileAuthRoute.path,
        name: ProfileAuthRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ProfileAuthScreen()),
      ),
      GoRoute(
        path: AllergiesRoute.path,
        name: AllergiesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AllergiesScreen()),
      ),
      GoRoute(
        path: DietRoute.path,
        name: DietRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: DietScreen()),
      ),
      GoRoute(
        path: DietAllergiesRoute.path,
        name: DietAllergiesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AllergiesScreen()),
      ),
      GoRoute(
        path: ShoppingListRoute.path,
        name: ShoppingListRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ShoppingPage()),
      ),
      GoRoute(
        path: NotificationsRoute.path,
        name: NotificationsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationsScreen()),
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
        path: LoginRoute.path,
        name: LoginRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: LoginScreen()),
      ),
      GoRoute(
        path: RegisterRoute.path,
        name: RegisterRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: RegisterScreen()),
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
      // Create Post
      GoRoute(
        path: CreatePostRoute.path,
        name: CreatePostRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatePostScreen()),
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
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
        path: '/channel/:channelId/post/:postId',
        name: 'channel_post_detail',
        pageBuilder: (context, state) {
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
        path: '/channel/:channelId/create-recipe',
        name: 'create_channel_recipe',
        pageBuilder: (context, state) {
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          final channelName =
              state.uri.queryParameters['channelName'] ?? 'канал';
          return MaterialPage(
            child: CreateChannelRecipeScreen(
              channelId: channelId,
              channelName: channelName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/create-post',
        name: 'create_channel_post',
        pageBuilder: (context, state) {
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
          final channelId = parseRoutePositiveId(state.pathParameters['channelId']);
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
        path: LegacyFavoritesRoute.path,
        name: LegacyFavoritesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage<void>(child: FavoritesPage()),
      ),
      GoRoute(
        path: UserSearchRoute.path,
        name: UserSearchRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage<void>(child: UserSearchPage()),
      ),
      // Search
      GoRoute(
        path: SearchRoute.path,
        name: SearchRoute.name,
        pageBuilder: (context, state) {
          final q = state.uri.queryParameters['q'];
          return MaterialPage<void>(
            child: SearchScreen(initialQuery: q),
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
      // Reels Fullscreen (при тапе на видео в ленте)
      GoRoute(
        path: ReelsFullscreenRoute.path,
        name: ReelsFullscreenRoute.name,
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
      child: Scaffold(
        appBar: AppBar(title: const Text('Ошибка')),
        body: AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Не удалось открыть страницу',
          subtitle: kDebugMode ? '${state.error}' : 'Попробуйте вернуться на главную',
          action: FilledButton(
            onPressed: () => context.go(FeedRoute.path),
            child: const Text('На главную'),
          ),
        ),
      ),
    ),
  );
});

class HistoryRoute {
  static const path = '/history';
  static const name = 'history';
}

class MenuRoute {
  static const path = '/';
  static const name = 'menu';
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

class AdminRefundQueueRoute {
  static const path = '/admin/refunds';
  static const name = 'admin_refunds';
}

class LegacyFavoritesRoute {
  static const path = '/favorites';
  static const name = 'legacy_favorites';
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

/// Вкладка «Профиль» в нижней навигации (хаб, не путать с [ProfileRoute] ленты профиля).
class ProfileTabRoute {
  static const path = '/me';
  static const name = 'profile_tab';
}

class SettingsRoute {
  static const path = '/settings';
  static const name = 'settings';
}

class MealPlanRoute {
  static const path = '/meal-plan';
  static const name = 'meal_plan';
}

class AiMealPlanRoute {
  static const path = '/meal-plan/ai';
  static const name = 'ai_meal_plan';
}

class MealPlanAnalyticsRoute {
  static const path = '/meal-plan/analytics';
  static const name = 'meal_plan_analytics';
}

class ScanResultRoute {
  static const path = '/scan-result';
  static const name = 'scan_result';
}

class CookingModeRoute {
  static const path = '/cooking-mode';
  static const name = 'cooking_mode';
}

class RecipeByIdRoute {
  static const path = '/recipe/:id';
  static const name = 'recipe_by_id';
}

class ShoppingImportRoute {
  static const path = '/shopping-import';
  static const name = 'shopping_import';
}

class CategoriesRoute {
  static const path = '/categories';
  static const name = 'categories';
}

class ProfileAuthRoute {
  static const path = '/profile-auth';
  static const name = 'profile_auth';
}

class AllergiesRoute {
  static const path = '/allergies';
  static const name = 'allergies';
}

class DietRoute {
  static const path = '/diet';
  static const name = 'diet';
}

class DietAllergiesRoute {
  static const path = '/diet-allergies';
  static const name = 'diet_allergies';
}

class ShoppingListRoute {
  static const path = '/shopping-list';
  static const name = 'shopping_list';
}

class NotificationsRoute {
  static const path = '/notifications';
  static const name = 'notifications';
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
  static const path = '/login';
  static const name = 'login';
}

class RegisterRoute {
  static const path = '/register';
  static const name = 'register';
}

class ForgotPasswordRoute {
  static const path = '/forgot-password';
  static const name = 'forgot_password';

  static String withEmail(String email) =>
      '$path?email=${Uri.encodeComponent(email)}';
}

class ResetPasswordRoute {
  static const path = '/reset-password';
  static const name = 'reset_password';
}

class VerifyEmailRoute {
  static const path = '/verify-email';
  static const name = 'verify_email';

  static String withEmail(String email) =>
      '$path?email=${Uri.encodeComponent(email)}';
}

class ConfirmEmailChangeRoute {
  static const path = '/confirm-email-change';
  static const name = 'confirm_email_change';
}

class AccountSecurityRoute {
  static const path = '/account-security';
  static const name = 'account_security';
}

class ProfileRoute {
  static const path = '/profile';
  static const name = 'profile';

  /// Ссылка на экран профиля с [userId] в query (как в GoRoute `/profile`).
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

  static String createRecipe(int channelId, String channelName) =>
      '${pathFor(channelId)}/create-recipe?channelName=${Uri.encodeComponent(channelName)}';

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

class SearchRoute {
  static const path = '/search';
  static const name = 'search';
}

class ReelsRoute {
  static const path = '/reels';
  static const name = 'reels';
}

class ReelsFullscreenRoute {
  static const path = '/reels/fullscreen';
  static const name = 'reels_fullscreen';
}
