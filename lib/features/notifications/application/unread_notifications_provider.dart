import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/notification_service.dart';
import '../../../services/user_realtime_service.dart';

class UnreadNotificationsNotifier extends StateNotifier<int> {
  UnreadNotificationsNotifier() : super(0) {
    refresh();
    _resetFallbackTimer();
    _realtimeSub = UserRealtimeService.instance.events.listen(_onRealtimeEvent);
    _connectedListener = () {
      if (!mounted) return;
      _resetFallbackTimer();
      if (UserRealtimeService.instance.connected.value) {
        unawaited(refresh());
      }
    };
    UserRealtimeService.instance.connected.addListener(_connectedListener!);
  }

  Timer? _timer;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;
  VoidCallback? _connectedListener;

  void _resetFallbackTimer() {
    _timer?.cancel();
    final seconds =
        UserRealtimeService.instance.connected.value ? 180 : 90;
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => refresh());
  }

  void _onRealtimeEvent(UserRealtimeEvent event) {
    if (!mounted) return;
    if (event.event == 'unread_counts' && event.notifications != null) {
      state = event.notifications!;
      return;
    }
    if (event.event == 'notification.new') {
      if (event.notifications != null) {
        state = event.notifications!;
        return;
      }
      unawaited(refresh());
      return;
    }
    if (event.event == 'sync') {
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
    if (_connectedListener != null) {
      UserRealtimeService.instance.connected.removeListener(_connectedListener!);
    }
    super.dispose();
  }
}

final unreadNotificationsCountProvider =
    StateNotifierProvider<UnreadNotificationsNotifier, int>(
  (ref) => UnreadNotificationsNotifier(),
);
