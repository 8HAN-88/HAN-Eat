import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/notification_service.dart';
import '../../../services/user_realtime_service.dart';

class UnreadNotificationsNotifier extends StateNotifier<int> {
  UnreadNotificationsNotifier() : super(0) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => refresh());
    _realtimeSub = UserRealtimeService.instance.events.listen(_onRealtimeEvent);
  }

  Timer? _timer;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;

  void _onRealtimeEvent(UserRealtimeEvent event) {
    if (!mounted) return;
    if (event.event == 'unread_counts' && event.notifications != null) {
      state = event.notifications!;
      return;
    }
    if (event.event == 'notification.new') {
      unawaited(refresh());
    }
  }

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
    _realtimeSub?.cancel();
    super.dispose();
  }
}

final unreadNotificationsCountProvider =
    StateNotifierProvider<UnreadNotificationsNotifier, int>(
  (ref) => UnreadNotificationsNotifier(),
);
