import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../features/notifications/application/unread_notifications_provider.dart';

/// Кнопка колокольчика с числом непрочитанных уведомлений.
class NotificationBellButton extends ConsumerStatefulWidget {
  const NotificationBellButton({super.key});

  @override
  ConsumerState<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends ConsumerState<NotificationBellButton>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(unreadNotificationsCountProvider);
    final label = count > 99 ? '99+' : '$count';

    return Badge(
      isLabelVisible: count > 0,
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.error,
      child: IconButton(
        icon: const Icon(Icons.notifications_outlined),
        tooltip: count > 0 ? 'Уведомления ($label)' : 'Уведомления',
        onPressed: () async {
          await context.push(NotificationsRoute.path);
          if (mounted) {
            await ref.read(unreadNotificationsCountProvider.notifier).refresh();
          }
        },
      ),
    );
  }
}
