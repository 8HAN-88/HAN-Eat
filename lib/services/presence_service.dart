import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'auth_service.dart';
import 'chat_service.dart';

/// Периодический heartbeat last_seen для чатов.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  Timer? _timer;
  bool _started = false;
  bool _appPaused = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ping();
    final interval = kIsWeb
        ? const Duration(seconds: 30)
        : const Duration(seconds: 60);
    _timer = Timer.periodic(interval, (_) {
      if (!_appPaused) _ping();
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
    if (!_appPaused && AuthService.instance.currentUser != null) {
      _ping();
    }
  }

  Future<void> _ping() async {
    if (AuthService.instance.currentUser == null) return;
    try {
      await ChatService.pingPresence();
    } catch (_) {}
  }
}
