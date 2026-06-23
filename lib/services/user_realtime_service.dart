import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import '../features/chat/application/chat_realtime_signals.dart';
import 'api_reachability_service.dart';
import 'auth_service.dart';
import 'notification_cache_service.dart';
import 'server_config.dart';

class UserRealtimeEvent {
  const UserRealtimeEvent({
    required this.event,
    this.notificationType,
    this.notifications,
  });

  final String event;
  final String? notificationType;
  final int? notifications;

  factory UserRealtimeEvent.fromJson(Map<String, dynamic> json) {
    final rawCount = json['notifications'] ?? json['unread_count'];
    int? count;
    if (rawCount is int) {
      count = rawCount;
    } else if (rawCount is num) {
      count = rawCount.toInt();
    }
    return UserRealtimeEvent(
      event: '${json['event'] ?? json['type'] ?? ''}',
      notificationType: json['notification_type'] as String?,
      notifications: count,
    );
  }
}

/// Единый SSE-поток пользователя: уведомления, счётчики, сигналы чата.
class UserRealtimeService {
  UserRealtimeService._();

  static final UserRealtimeService instance = UserRealtimeService._();

  static bool _initialized = false;
  static void Function(User?)? _sessionListener;
  static VoidCallback? _reconnectListener;

  final StreamController<UserRealtimeEvent> _events =
      StreamController<UserRealtimeEvent>.broadcast();
  final ValueNotifier<bool> connected = ValueNotifier(false);

  Stream<UserRealtimeEvent> get events => _events.stream;

  StreamSubscription<List<int>>? _subscription;
  http.Client? _client;
  bool _disposed = false;
  String _buffer = '';
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  int _reconnectAttempt = 0;
  DateTime _lastActivity = DateTime.now();
  final _random = math.Random();

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _sessionListener = (user) {
      if (user != null) {
        instance.connect();
      } else {
        instance.disconnect();
        unawaited(NotificationCacheService.clear());
      }
    };
    AuthService.registerSessionListener(_sessionListener!);

    _reconnectListener = () => instance.resume();
    ApiReachabilityService.addReconnectedListener(_reconnectListener!);

    if (AuthService.instance.currentUser != null) {
      instance.connect();
    }
  }

  void connect() {
    if (_disposed) {
      _disposed = false;
    }
    _reconnectTimer?.cancel();
    unawaited(_openStream());
  }

  void pause() {
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    if (connected.value) {
      connected.value = false;
    }
  }

  void resume() {
    if (_disposed) return;
    if (AuthService.instance.currentUser == null) return;
    connect();
  }

  void disconnect() {
    _disposed = true;
    pause();
    _client?.close();
    _client = null;
  }

  Future<void> _openStream() async {
    if (_disposed) return;
    _subscription?.cancel();

    try {
      final token = await AuthService.getAccessTokenForApi();
      if (token == null || _disposed) return;

      final uri = Uri.parse('${ServerConfig.apiBaseUrl}/realtime/stream');
      final request = http.Request('GET', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });

      _client = HanEatHttpClient.shared;
      final response = await _client!.send(request).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('SSE connect timeout'),
      );
      if (response.statusCode == 401) {
        await AuthService.refreshToken();
        if (!_disposed) _scheduleReconnect();
        return;
      }
      if (response.statusCode != 200) {
        if (!_disposed) _scheduleReconnect();
        return;
      }

      _reconnectAttempt = 0;
      _lastActivity = DateTime.now();
      _startWatchdog();
      if (!connected.value) {
        connected.value = true;
      }

      _buffer = '';
      _subscription = response.stream.listen(
        _onBytes,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('UserRealtimeService: $e');
      _handleDisconnect();
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed || !connected.value) return;
      final idle = DateTime.now().difference(_lastActivity);
      if (idle > const Duration(seconds: 50)) {
        debugPrint('UserRealtimeService: idle ${idle.inSeconds}s, reconnecting');
        _handleDisconnect(forceReconnect: true);
      }
    });
  }

  void _onBytes(List<int> bytes) {
    _lastActivity = DateTime.now();
    _buffer += utf8.decode(bytes, allowMalformed: true);
    while (_buffer.contains('\n\n')) {
      final split = _buffer.indexOf('\n\n');
      final block = _buffer.substring(0, split);
      _buffer = _buffer.substring(split + 2);
      if (block.startsWith(':')) continue;
      for (final line in block.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final raw = line.substring(5).trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          final event = UserRealtimeEvent.fromJson(decoded);
          if (event.event.isEmpty || event.event == 'ping') continue;
          _events.add(event);
          if (event.notificationType == 'message') {
            ChatRealtimeSignals.instance.notifyNewMessage();
          }
        } catch (_) {}
      }
    }
  }

  void _handleDisconnect({bool forceReconnect = false}) {
    if (_disposed && !forceReconnect) return;
    _watchdogTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    if (connected.value) {
      connected.value = false;
    }
    if (forceReconnect || !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (AuthService.instance.currentUser == null) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 20);
    final baseSec = math.min(1 + _reconnectAttempt, 15);
    final jitterMs = _random.nextInt(800);
    final delay = Duration(seconds: baseSec, milliseconds: jitterMs);
    _reconnectTimer = Timer(delay, connect);
  }
}
