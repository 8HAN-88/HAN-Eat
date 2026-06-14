import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import 'auth_service.dart';
import 'server_config.dart';

typedef ChatStreamEventHandler = void Function(Map<String, dynamic> event);

/// SSE-подписка на события чата (новые сообщения, typing, удаление).
class ChatStreamService {
  ChatStreamService({
    required this.conversationId,
    required this.onEvent,
    this.onConnected,
    this.onDisconnected,
  });

  final int conversationId;
  final ChatStreamEventHandler onEvent;
  final VoidCallback? onConnected;
  final VoidCallback? onDisconnected;

  StreamSubscription<List<int>>? _subscription;
  http.Client? _client;
  bool _disposed = false;
  bool connected = false;
  String _buffer = '';
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  int _reconnectAttempt = 0;
  DateTime _lastActivity = DateTime.now();
  final _random = math.Random();

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    unawaited(_openStream());
  }

  void pause() {
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    if (connected) {
      connected = false;
      onDisconnected?.call();
    }
  }

  void resume() {
    if (_disposed) return;
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

      final uri = Uri.parse(
        '${ServerConfig.apiBaseUrl}/chats/$conversationId/stream',
      );
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
      if (!connected) {
        connected = true;
        onConnected?.call();
      }

      _buffer = '';
      _subscription = response.stream.listen(
        _onBytes,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('ChatStreamService: $e');
      _handleDisconnect();
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed || !connected) return;
      final idle = DateTime.now().difference(_lastActivity);
      if (idle > const Duration(seconds: 50)) {
        debugPrint('ChatStreamService: idle ${idle.inSeconds}s, reconnecting');
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
          if (decoded is Map<String, dynamic>) {
            final type = decoded['type']?.toString();
            if (type == 'ping') continue;
            onEvent(decoded);
          }
        } catch (_) {}
      }
    }
  }

  void _handleDisconnect({bool forceReconnect = false}) {
    if (_disposed) return;
    _watchdogTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    if (connected) {
      connected = false;
      onDisconnected?.call();
    }
    if (forceReconnect || !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 20);
    final baseSec = math.min(1 + _reconnectAttempt, 15);
    final jitterMs = _random.nextInt(800);
    final delay = Duration(seconds: baseSec, milliseconds: jitterMs);
    _reconnectTimer = Timer(delay, connect);
  }
}
