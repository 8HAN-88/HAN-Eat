import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/feed_scroll_chrome.dart';
import '../../chat/application/chats_hub_search.dart';
import '../application/app_search_context.dart';
import '../application/shell_tab_visibility.dart';
import '../../menu/application/menu_recommendations_refresh_provider.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../../../../services/account_session_service.dart';
import '../../../../services/api_service.dart';
import '../../../../services/api_reachability_service.dart';
import '../../../../widgets/connectivity_status_banner.dart';
import '../../../../widgets/pwa_install_banner.dart';
import '../../../../services/feed_sync_service.dart';
import '../../../../services/chat_service.dart';
import '../../../../services/presence_service.dart';
import '../../../../services/auth_service.dart';
import '../../chat/application/channel_inbox_badge.dart';
import '../../chat/application/chats_hub_refresh_provider.dart';
import '../../chat/application/chat_realtime_signals.dart';
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
  int _unreadDmCount = 0;
  int _unreadChannelCount = 0;
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
    _startPeriodicUpdate();
    _chatSignalsSub =
        ChatRealtimeSignals.instance.hubRefresh.listen((_) {
      if (mounted) _loadChatUnreadCount();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AuthService.instance.currentUser != null) {
        PresenceService.instance.start();
      }
      // Не конкурируем с лентой при холодном старте — бейджи чуть позже.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) _loadChatUnreadCount();
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) unawaited(ApiReachabilityService.instance.warmUp());
      });
    });
    _apiReachabilityListener = () {
      if (!mounted) return;
      if (ApiReachabilityService.instance.isApiReachable.value) {
        _loadChatUnreadCount();
      }
    };
    ApiReachabilityService.instance.isApiReachable
        .addListener(_apiReachabilityListener!);
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
    Future.delayed(const Duration(seconds: 90), () {
      if (mounted) {
        unawaited(ApiReachabilityService.instance.checkNow());
        _loadChatUnreadCount();
        _startPeriodicUpdate();
      }
    });
  }

  StreamSubscription<void>? _chatSignalsSub;
  VoidCallback? _apiReachabilityListener;

  @override
  void dispose() {
    _chatSignalsSub?.cancel();
    if (_apiReachabilityListener != null) {
      ApiReachabilityService.instance.isApiReachable
          .removeListener(_apiReachabilityListener!);
    }
    super.dispose();
  }

  Future<void> _loadChatUnreadCount() async {
    try {
      final chatCount = await ChatService.unreadCount();
      final channelNew = await ChannelInboxBadge.countNewPosts();
      if (mounted) {
        setState(() {
          _unreadDmCount = chatCount;
          _unreadChannelCount = channelNew;
          _unreadChatCount = chatCount + channelNew;
        });
      }
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
    resetShellNavCompact();

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

    if (online) {
      return ShellScrollChromeListener(child: child);
    }
    return ShellScrollChromeListener(
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellChatBadgeRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        _loadChatUnreadCount();
      }
    });
    ref.listen<int>(chatsHubRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        _loadChatUnreadCount();
      }
    });

    final scheme = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return ValueListenableBuilder<bool>(
      valueListenable: shellNavCompact,
      builder: (context, compact, _) {
        final shellIndex =
            _clampShellIndex(widget.navigationShell.currentIndex);
        final navHeight =
            compact ? kShellNavCompactHeight : kShellNavExpandedHeight;
        final iconSize = compact ? 22.0 : 26.0;
        final searchPath = contextualSearchPath(shellIndex);
        final chatsInlineSearch = usesChatsHubInlineSearch(shellIndex);
        final showSearchButton = searchPath != null || chatsInlineSearch;
        final navDuration =
            compact ? kShellNavCompactDuration : kShellNavExpandDuration;

        final navBar = SafeArea(
          minimum: EdgeInsets.only(
            left: kShellNavSideMargin,
            right: kShellNavSideMargin,
            bottom: compact
                ? kShellNavBottomMarginCompact
                : kShellNavBottomMarginExpanded,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ShellNavGlassPill(
                  height: navHeight,
                  compact: compact,
                  duration: navDuration,
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      height: navHeight,
                      labelTextStyle:
                          WidgetStateProperty.all(const TextStyle(fontSize: 0)),
                      iconTheme: WidgetStateProperty.resolveWith(
                        (states) => IconThemeData(
                          size: states.contains(WidgetState.selected)
                              ? iconSize + 1
                              : iconSize,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      height: navHeight,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysHide,
                      selectedIndex: shellIndex,
                      onDestinationSelected: _onDestinationSelected,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      indicatorColor: scheme.primary.withValues(alpha: 0.18),
                      destinations: [
                        for (var i = 0;
                            i < RootShell._destinations.length;
                            i++)
                          _buildNavigationDestination(
                            RootShell._destinations[i],
                            badgeLabel: _badgeLabelForTab(i),
                            badgeTooltip: i == 1
                                ? _chatTabBadgeTooltip()
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (showSearchButton) ...[
                const SizedBox(width: 10),
                _ShellNavGlassPill(
                  height: navHeight,
                  compact: compact,
                  duration: navDuration,
                  child: IconButton(
                    tooltip: 'Поиск',
                    icon: Icon(Icons.search_rounded, size: iconSize),
                    onPressed: () {
                      if (chatsInlineSearch) {
                        requestChatsHubSearchOpen();
                        return;
                      }
                      context.push(searchPath!);
                    },
                  ),
                ),
              ],
            ],
          ),
        );

        return Scaffold(
          backgroundColor: pageBg,
          extendBody: true,
          body: ListenableBuilder(
            listenable: Listenable.merge([
              FeedSyncService.onlineListenable,
              ApiReachabilityService.instance.isApiReachable,
            ]),
            builder: (context, _) {
              final online = FeedSyncService.onlineListenable.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConnectivityStatusBanner(),
                  const PwaInstallBanner(),
                  _subscriptionStaleBanner(context),
                  Expanded(
                    child: _navigationContent(context, online: online),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: navBar,
        );
      },
    );
  }

  String? _chatTabBadgeLabel() {
    if (_unreadDmCount <= 0 && _unreadChannelCount <= 0) return null;
    if (_unreadDmCount > 0 && _unreadChannelCount > 0) {
      final dm = _unreadDmCount > 99 ? '99+' : '$_unreadDmCount';
      final ch = _unreadChannelCount > 99 ? '99+' : '$_unreadChannelCount';
      return '$dm·$ch';
    }
    final single = _unreadDmCount > 0 ? _unreadDmCount : _unreadChannelCount;
    return single > 99 ? '99+' : '$single';
  }

  String? _chatTabBadgeTooltip() {
    if (_unreadDmCount <= 0 && _unreadChannelCount <= 0) return null;
    return 'Чаты: $_unreadDmCount · Каналы: $_unreadChannelCount';
  }

  String? _badgeLabelForTab(int index) {
    if (index == 1) return _chatTabBadgeLabel();
    return null;
  }

  Widget _buildNavigationDestination(
    _NavDestination destination, {
    String? badgeLabel,
    String? badgeTooltip,
  }) {
    Widget icon = Icon(destination.icon);
    Widget selectedIcon = Icon(destination.selectedIcon);

    if (badgeLabel != null && badgeLabel.isNotEmpty) {
      icon = Badge(
        label: Text(
          badgeLabel,
          style: const TextStyle(fontSize: 10),
        ),
        child: icon,
      );
      selectedIcon = Badge(
        label: Text(
          badgeLabel,
          style: const TextStyle(fontSize: 10),
        ),
        child: selectedIcon,
      );
    }

    return Semantics(
      label: badgeTooltip ?? destination.label,
      child: NavigationDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: '',
      ),
    );
  }
}

/// Полупрозрачная «таблетка» нижней панели (blur + pill), как в Instagram.
class _ShellNavGlassPill extends StatelessWidget {
  const _ShellNavGlassPill({
    required this.height,
    required this.compact,
    required this.duration,
    required this.child,
  });

  final double height;
  final bool compact;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = height / 2;
    final fill = isDark
        ? Colors.black.withValues(alpha: compact ? 0.52 : 0.62)
        : scheme.surface.withValues(alpha: compact ? 0.68 : 0.78);
    final blur = compact ? 14.0 : 20.0;

    return AnimatedContainer(
      duration: duration,
      curve: kShellNavChromeCurve,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: compact ? 12 : 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
              ),
            ),
            child: child,
          ),
        ),
      ),
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
