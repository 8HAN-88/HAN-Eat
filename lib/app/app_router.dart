import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:typed_data';

import '../features/community/presentation/community_screen.dart';
import '../features/community/presentation/communities_list_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/menu/presentation/menu_screen.dart';
import '../features/menu/presentation/scan_result_screen.dart';
import '../screens/cooking_mode_screen.dart';
import '../screens/recipe_by_id_screen.dart';
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
import '../features/settings/notification_settings_page.dart';
import '../features/meal_plan/presentation/meal_plan_screen.dart';
import '../features/shopping/shopping_page.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/posts/presentation/create_post_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/feed/presentation/main_feed_screen.dart';
import '../features/comments/presentation/comments_screen.dart';
import '../features/channels/presentation/channels_list_screen.dart';
import '../features/channels/presentation/channels_main_screen.dart';
import '../features/channels/presentation/channel_page_screen.dart';
import '../features/channels/presentation/channel_detail_screen.dart';
import '../features/channels/presentation/channel_posts_screen.dart';
import '../features/channels/presentation/channel_post_detail_screen.dart';
import '../features/channels/presentation/channels_management_screen.dart';
import '../features/channels/presentation/create_channel_screen.dart';
import '../features/channels/presentation/create_channel_recipe_screen.dart';
import '../features/channels/presentation/create_channel_post_screen.dart';
import '../features/channels/presentation/channel_settings_screen.dart';
import '../features/channels/presentation/channel_management_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/moderation/presentation/moderation_queue_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/reels/presentation/reels_feed_screen.dart';
import '../features/reels/presentation/reels_fullscreen_screen.dart';
import '../services/auth_service.dart';
import 'bootstrap.dart';

String? _parseDeepLink(String raw) {
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
  } catch (_) {}
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final initialLoc = () {
    if (initialDeepLink != null) {
      final path = _parseDeepLink(initialDeepLink!);
      initialDeepLink = null;
      if (path != null) return path;
    }
    return FeedRoute.path;
  }();
  return GoRouter(
    initialLocation: initialLoc,
    redirect: (context, state) {
      final isAuth = AuthService.instance.currentUser != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == LoginRoute.path ||
          loc == RegisterRoute.path ||
          loc == ProfileAuthRoute.path;
      if (!isAuth && !isAuthRoute) return ProfileAuthRoute.path;
      return null;
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
                pageBuilder: (context, state) =>
                    NoTransitionPage(
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
                pageBuilder: (context, state) =>
                    NoTransitionPage(
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
                pageBuilder: (context, state) =>
                    NoTransitionPage(
                      key: const ValueKey('menu_branch'),
                      child: const MenuScreen(),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SettingsRoute.path,
                name: SettingsRoute.name,
                pageBuilder: (context, state) =>
                    NoTransitionPage(
                      key: const ValueKey('settings_branch'),
                      child: const SettingsScreen(),
                    ),
              ),
            ],
          ),
        ],
      ),
      // Отдельный маршрут для плана питания
      GoRoute(
        path: MealPlanRoute.path,
        name: MealPlanRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MealPlanScreen()),
      ),
      // Результат сканирования блюда (фото → питательность и рецепты)
      GoRoute(
        path: ScanResultRoute.path,
        name: ScanResultRoute.name,
        pageBuilder: (context, state) {
          final bytes = state.extra is Uint8List ? state.extra as Uint8List : null;
          if (bytes == null) {
            return MaterialPage(
              child: Scaffold(
                appBar: AppBar(title: const Text('Error')),
                body: const Center(child: Text('No image data')),
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
            return MaterialPage(
              child: Scaffold(
                appBar: AppBar(title: const Text('Режим готовки')),
                body: const Center(child: Text('Рецепт не передан')),
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
            return MaterialPage(
              child: Scaffold(
                appBar: AppBar(title: const Text('Рецепт')),
                body: const Center(child: Text('Неверная ссылка на рецепт')),
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
        path: SubscriptionRoute.path,
        name: SubscriptionRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SubscriptionScreen()),
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
      // Comments
      GoRoute(
        path: '/post/:postId/comments',
        name: 'post_comments',
        pageBuilder: (context, state) {
          final postId = int.parse(state.pathParameters['postId']!);
          return MaterialPage(child: CommentsScreen(postId: postId));
        },
      ),
      // Channels
      GoRoute(
        path: '/channel/:channelId',
        name: 'channel_page',
        pageBuilder: (context, state) {
          final channelId = int.parse(state.pathParameters['channelId']!);
          return MaterialPage(child: ChannelPostsScreen(channelId: channelId));
        },
      ),
      GoRoute(
        path: '/channel/:channelId/info',
        name: 'channel_detail',
        pageBuilder: (context, state) {
          final channelId = int.parse(state.pathParameters['channelId']!);
          return MaterialPage(child: ChannelDetailScreen(channelId: channelId));
        },
      ),
      GoRoute(
        path: '/channel/:channelId/post/:postId',
        name: 'channel_post_detail',
        pageBuilder: (context, state) {
          final channelId = int.parse(state.pathParameters['channelId']!);
          final postId = int.parse(state.pathParameters['postId']!);
          return MaterialPage(
            child: ChannelPostDetailScreen(
              channelId: channelId,
              postId: postId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channels/management',
        name: 'channels_management',
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
          final channelId = int.parse(state.pathParameters['channelId']!);
          final channelName = state.uri.queryParameters['channelName'] ?? 'канал';
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
          final channelId = int.parse(state.pathParameters['channelId']!);
          final channelName = state.uri.queryParameters['channelName'] ?? 'канал';
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
          final channelId = int.parse(state.pathParameters['channelId']!);
          final postId = int.parse(state.pathParameters['postId']!);
          final postData = state.extra as Map<String, dynamic>?;
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
          final channelId = int.parse(state.pathParameters['channelId']!);
          final channelName = state.uri.queryParameters['channelName'] ?? 'канал';
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
          final channelId = int.parse(state.pathParameters['channelId']!);
          return MaterialPage(
            child: ChannelManagementScreen(channelId: channelId),
          );
        },
      ),
      // Notifications List (удален дубликат - используется NotificationsRoute выше)
      // Support
      GoRoute(
        path: '/support',
        name: 'support',
        pageBuilder: (context, state) =>
            const MaterialPage(child: SupportScreen()),
      ),
      // Analytics
      GoRoute(
        path: '/analytics',
        name: 'analytics',
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
        path: '/moderation',
        name: 'moderation',
        pageBuilder: (context, state) =>
            const MaterialPage(child: ModerationQueueScreen()),
      ),
      // Search
      GoRoute(
        path: SearchRoute.path,
        name: SearchRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SearchScreen()),
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
          final post = state.extra as dynamic;
          return MaterialPage(
            child: ReelsFullscreenScreen(initialPost: post),
          );
        },
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        body: Center(
          child: Text(
            'Хьюстон, у нас ошибка маршрута: ${state.error}',
            textAlign: TextAlign.center,
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

class ChannelsListRoute {
  static const path = '/channels';
  static const name = 'channels';
}

class FeedRoute {
  static const path = '/feed';
  static const name = 'feed';
}

class SettingsRoute {
  static const path = '/settings';
  static const name = 'settings';
}

class MealPlanRoute {
  static const path = '/meal-plan';
  static const name = 'meal_plan';
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

class SubscriptionRoute {
  static const path = '/subscription';
  static const name = 'subscription';
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

class ProfileRoute {
  static const path = '/profile';
  static const name = 'profile';
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
