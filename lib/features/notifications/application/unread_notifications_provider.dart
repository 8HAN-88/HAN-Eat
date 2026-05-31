import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/notification_service.dart';

class UnreadNotificationsNotifier extends StateNotifier<int> {
  UnreadNotificationsNotifier() : super(0) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Timer? _timer;

  Future<void> refresh() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) state = count;
    } catch (_) {
      // оставляем предыдущее значение
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final unreadNotificationsCountProvider =
    StateNotifierProvider<UnreadNotificationsNotifier, int>(
  (ref) => UnreadNotificationsNotifier(),
);
