import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../../../../services/notification_service.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _NavDestination(label: 'Главная', icon: Icons.home_outlined, hasNotifications: true),
    _NavDestination(label: 'Каналы', icon: Icons.cable_outlined),
    _NavDestination(label: 'Menu', icon: Icons.grid_view_rounded),
    _NavDestination(label: 'Настройки', icon: Icons.settings_outlined),
  ];

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _unreadNotificationsCount = 0;
  
  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    // Обновляем счетчик каждые 30 секунд
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
  
  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) {
        setState(() => _unreadNotificationsCount = count);
      }
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    
    // Если переходим на главную, обновляем счетчик уведомлений
    if (index == 0) {
      _loadUnreadCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OnboardingOverlay(
        child: widget.navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (var i = 0; i < RootShell._destinations.length; i++)
            _buildNavigationDestination(RootShell._destinations[i], i == 0),
        ],
      ),
    );
  }
  
  Widget _buildNavigationDestination(_NavDestination destination, bool isHome) {
    Widget icon = Icon(destination.icon);
    
    // Для главной: показываем точку, если есть непрочитанные уведомления
    if (isHome && _unreadNotificationsCount > 0) {
      icon = Badge(
        smallSize: 8,
        child: icon,
      );
    }
    
    return NavigationDestination(
      icon: icon,
      label: destination.label,
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.icon,
    this.hasNotifications = false,
  });

  final String label;
  final IconData icon;
  final bool hasNotifications;
}
