import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../menu/application/menu_recommendations_refresh_provider.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../../../../services/account_session_service.dart';
import '../../../../services/api_service.dart';
import '../../../../services/feed_sync_service.dart';
import '../../../../services/notification_service.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _NavDestination(
      label: 'Главная',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      hasNotifications: true,
    ),
    _NavDestination(
      label: 'Каналы',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed_rounded,
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
  int _unreadNotificationsCount = 0;
  int _unreadLoadFailures = 0;
  bool _unreadRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _startPeriodicUpdate();
  }

  void _startPeriodicUpdate() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _loadUnreadCount();
        _startPeriodicUpdate();
      }
    });
  }

  void _scheduleUnreadRetry() {
    if (_unreadRetryScheduled || _unreadLoadFailures >= 3) return;
    _unreadRetryScheduled = true;
    final delay = Duration(seconds: 10 * _unreadLoadFailures.clamp(1, 3));
    Future.delayed(delay, () {
      _unreadRetryScheduled = false;
      if (mounted) _loadUnreadCount();
    });
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) {
        setState(() {
          _unreadNotificationsCount = count;
          _unreadLoadFailures = 0;
        });
      }
    } catch (e) {
      debugPrint('Unread notifications count: $e');
      if (!mounted) return;
      setState(() => _unreadLoadFailures++);
      _scheduleUnreadRetry();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );

    if (index == 0) {
      _loadUnreadCount();
    }
    // Вкладка «Меню» — свежие рекомендации + баланс AI scan.
    if (index == 2) {
      ref.read(menuRecommendationsRefreshProvider.notifier).state++;
      unawaited(ApiService.touchAiScanCreditsSilently());
    }
  }

  Widget _offlineBanner(BuildContext context) {
    try {
      final scheme = Theme.of(context).colorScheme;
      return ValueListenableBuilder<bool>(
        valueListenable: FeedSyncService.instance.isOnline,
        builder: (context, online, _) {
          if (online) return const SizedBox.shrink();
          return Material(
            color: scheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 20,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Нет подключения к сети. Сохранённые ленты и кэш '
                        'могут открываться без интернета.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                              height: 1.35,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: pageBg,
      extendBody: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _offlineBanner(context),
          Expanded(
            child: OnboardingOverlay(
              child: ValueListenableBuilder<int>(
                valueListenable: AccountSessionService.epoch,
                builder: (context, sessionEpoch, _) {
                  return KeyedSubtree(
                    key: ValueKey('main_shell_session_$sessionEpoch'),
                    child: widget.navigationShell,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              height: 68,
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              backgroundColor: pageBg,
              elevation: 4,
              shadowColor: scheme.shadow.withValues(alpha: 0.15),
              surfaceTintColor: Colors.transparent,
              indicatorColor: scheme.primary.withValues(alpha: 0.14),
              destinations: [
                for (var i = 0; i < RootShell._destinations.length; i++)
                  _buildNavigationDestination(RootShell._destinations[i], i == 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationDestination(_NavDestination destination, bool isHome) {
    Widget icon = Icon(destination.icon);
    Widget selectedIcon = Icon(destination.selectedIcon);

    if (isHome && _unreadNotificationsCount > 0) {
      icon = Badge(
        smallSize: 8,
        child: icon,
      );
      selectedIcon = Badge(
        smallSize: 8,
        child: selectedIcon,
      );
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
    this.hasNotifications = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool hasNotifications;
}
