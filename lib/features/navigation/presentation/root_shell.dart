import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/feed_scroll_chrome.dart';
import '../../chat/application/chats_hub_search.dart';
import '../application/app_search_context.dart';
import '../application/root_shell_chrome.dart';
import '../application/shell_tab_visibility.dart';
import '../../menu/application/menu_recommendations_refresh_provider.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../services/account_session_service.dart';
import '../../../../services/api_service.dart';
import '../../../../services/feed_sync_service.dart';
import '../../../../services/chat_service.dart';
import '../../../../services/presence_service.dart';
import '../../../../services/auth_service.dart';
import '../../chat/application/channel_inbox_badge.dart';
import '../../chat/application/chats_hub_refresh_provider.dart';
import '../application/shell_chat_badge_refresh_provider.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _NavDestination(
      label: 'Главная',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavDestination(
      label: 'Чаты',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      hasChatUnread: true,
    ),
    _NavDestination(
      label: 'Меню',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
    ),
    _NavDestination(
      label: 'Профиль',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _unreadChatCount = 0;
  bool _shellIndexFixScheduled = false;

  static int _clampShellIndex(int index) =>
      index.clamp(0, RootShell._destinations.length - 1);

  int _syncShellTabVisibility(int index, {bool deferIfBuilding = false}) {
    final safe = _clampShellIndex(index);
    if (ShellTabVisibility.activeIndex.value == safe) return safe;

    void apply() {
      if (ShellTabVisibility.activeIndex.value != safe) {
        ShellTabVisibility.activeIndex.value = safe;
      }
    }

    if (deferIfBuilding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return safe;
  }

  /// Сбрасывает сохранённый индекс вкладки (5→4) без goBranch во время build.
  void _scheduleShellIndexFixIfNeeded() {
    final raw = widget.navigationShell.currentIndex;
    final safe = _syncShellTabVisibility(raw);
    if (raw == safe || _shellIndexFixScheduled) return;
    _shellIndexFixScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shellIndexFixScheduled = false;
      if (!mounted) return;
      final current = widget.navigationShell.currentIndex;
      final target = _clampShellIndex(current);
      _syncShellTabVisibility(target);
      if (current != target) {
        widget.navigationShell.goBranch(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final raw = widget.navigationShell.currentIndex;
      final safe = _syncShellTabVisibility(raw);
      if (raw != safe) {
        widget.navigationShell.goBranch(safe);
      }
    });
    _loadChatUnreadCount();
    _startPeriodicUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AuthService.instance.currentUser != null) {
        PresenceService.instance.start();
      }
    });
  }

  @override
  void didUpdateWidget(covariant RootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      _syncShellTabVisibility(
        widget.navigationShell.currentIndex,
        deferIfBuilding: true,
      );
    }
    _scheduleShellIndexFixIfNeeded();
  }

  void _startPeriodicUpdate() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _loadChatUnreadCount();
        _startPeriodicUpdate();
      }
    });
  }

  Future<void> _loadChatUnreadCount() async {
    try {
      final chatCount = await ChatService.unreadCount();
      final channelNew = await ChannelInboxBadge.countNewPosts();
      final total = chatCount + channelNew;
      if (mounted) setState(() => _unreadChatCount = total);
    } catch (e) {
      debugPrint('Unread chat count: $e');
    }
  }

  void _onDestinationSelected(int index) {
    final safe = _syncShellTabVisibility(index);
    widget.navigationShell.goBranch(
      safe,
      initialLocation: safe == widget.navigationShell.currentIndex,
    );

    if (index != 0) {
      resetFeedScrollChrome();
    }

    if (index == 1) {
      _loadChatUnreadCount();
      ref.read(chatsHubRefreshProvider.notifier).state++;
    }
    // Вкладка «Меню» — свежие рекомендации + баланс AI scan.
    if (index == 2) {
      ref.read(menuRecommendationsRefreshProvider.notifier).state++;
      unawaited(ApiService.touchAiScanCreditsSilently());
    }
  }

  Widget _subscriptionStaleBanner(BuildContext context) {
    final stale = ref.watch(subscriptionStatusFromCacheProvider);
    if (!stale) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Не удалось обновить подписку — показан сохранённый тариф',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => refreshSubscriptionStatus(ref),
                child: const Text('Обновить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offlineBanner(BuildContext context, bool online) {
    try {
      if (online) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Нет сети. Лента, избранное и недавние чаты доступны офлайн.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                          height: 1.2,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _navigationContent(BuildContext context, {required bool online}) {
    final child = OnboardingOverlay(
      child: ValueListenableBuilder<int>(
        valueListenable: AccountSessionService.epoch,
        builder: (context, sessionEpoch, _) {
          return KeyedSubtree(
            key: ValueKey('main_shell_session_$sessionEpoch'),
            child: widget.navigationShell,
          );
        },
      ),
    );

    if (online) return child;
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellChatBadgeRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        _loadChatUnreadCount();
      }
    });

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return ValueListenableBuilder<bool>(
      valueListenable: rootShellHideBottomNav,
      builder: (context, hideBottomNav, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: feedScrollChromeHidden,
          builder: (context, feedChromeHidden, __) {
            final shellIndex =
                _clampShellIndex(widget.navigationShell.currentIndex);
            final hideForReels = hideBottomNav && shellIndex == 0;
            final hideForFeedScroll = shellIndex == 0 && feedChromeHidden;
            final hideNav = hideForReels || hideForFeedScroll;

            final navShadow = scheme.shadow.withValues(alpha: 0.15);
            final searchPath = contextualSearchPath(shellIndex);
            final chatsInlineSearch = usesChatsHubInlineSearch(shellIndex);
            final showSearchButton = searchPath != null || chatsInlineSearch;
            final navBar = SafeArea(
              minimum: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.nav),
                        child: NavigationBarTheme(
                          data: NavigationBarThemeData(
                            height: AppSizes.floatingNavHeight,
                            labelTextStyle: WidgetStateProperty.resolveWith(
                              (states) => textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                height: 1.1,
                              ),
                            ),
                            iconTheme: WidgetStateProperty.resolveWith(
                              (states) => IconThemeData(
                                size: states.contains(WidgetState.selected)
                                    ? 22
                                    : 21,
                              ),
                            ),
                          ),
                          child: NavigationBar(
                            height: AppSizes.floatingNavHeight,
                            labelBehavior:
                                NavigationDestinationLabelBehavior.alwaysShow,
                            selectedIndex: shellIndex,
                            onDestinationSelected: _onDestinationSelected,
                            backgroundColor: pageBg,
                            elevation: 4,
                            shadowColor: navShadow,
                            surfaceTintColor: Colors.transparent,
                            indicatorColor:
                                scheme.primary.withValues(alpha: 0.14),
                            destinations: [
                              for (var i = 0;
                                  i < RootShell._destinations.length;
                                  i++)
                                _buildNavigationDestination(
                                  RootShell._destinations[i],
                                  badgeCount: _badgeCountForTab(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showSearchButton) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: pageBg,
                      elevation: 4,
                      shadowColor: navShadow,
                      borderRadius: BorderRadius.circular(AppRadius.nav),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: AppSizes.floatingNavSearchSize,
                        height: AppSizes.floatingNavSearchSize,
                        child: IconButton(
                          tooltip: 'Поиск',
                          icon: const Icon(Icons.search_rounded, size: 22),
                          onPressed: () {
                            if (chatsInlineSearch) {
                              requestChatsHubSearchOpen();
                              return;
                            }
                            context.push(searchPath!);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );

            return Scaffold(
              backgroundColor: pageBg,
              extendBody: true,
              body: ValueListenableBuilder<bool>(
                valueListenable: FeedSyncService.onlineListenable,
                builder: (context, online, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _offlineBanner(context, online),
                      _subscriptionStaleBanner(context),
                      Expanded(
                        child: _navigationContent(context, online: online),
                      ),
                    ],
                  );
                },
              ),
              bottomNavigationBar: ClipRect(
                child: AnimatedAlign(
                  duration: kFeedScrollChromeDuration,
                  curve: kFeedScrollChromeCurve,
                  alignment: Alignment.topCenter,
                  heightFactor: hideNav ? 0 : 1,
                  child: AnimatedOpacity(
                    duration: kFeedScrollChromeDuration,
                    curve: kFeedScrollChromeCurve,
                    opacity: hideNav ? 0 : 1,
                    child: IgnorePointer(
                      ignoring: hideNav,
                      child: navBar,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int? _badgeCountForTab(int index) {
    if (index == 1 && _unreadChatCount > 0) {
      return _unreadChatCount;
    }
    return null;
  }

  Widget _buildNavigationDestination(
    _NavDestination destination, {
    int? badgeCount,
  }) {
    Widget icon = Icon(destination.icon);
    Widget selectedIcon = Icon(destination.selectedIcon);

    if (badgeCount != null && badgeCount > 0) {
      final label = badgeCount > 99 ? '99+' : '$badgeCount';
      icon = Badge(label: Text(label), child: icon);
      selectedIcon = Badge(label: Text(label), child: selectedIcon);
    }

    return NavigationDestination(
      icon: icon,
      selectedIcon: selectedIcon,
      label: destination.label,
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.hasChatUnread = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool hasChatUnread;
}
