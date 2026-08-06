import 'dart:async';

import '../../../core/platform/device_location.dart';
import '../../../services/chat_service.dart';

/// Foreground live-location updater for one outgoing message.
class LiveLocationSession {
  LiveLocationSession({
    required this.conversationId,
    required this.messageId,
    required this.expiresAt,
  });

  static final Map<int, LiveLocationSession> _active = {};

  final int conversationId;
  final int messageId;
  final DateTime expiresAt;
  Timer? _timer;
  bool _stopped = false;

  static LiveLocationSession? activeFor(int messageId) => _active[messageId];

  static void start({
    required int conversationId,
    required int messageId,
    required DateTime expiresAt,
  }) {
    stopLocal(messageId);
    final session = LiveLocationSession(
      conversationId: conversationId,
      messageId: messageId,
      expiresAt: expiresAt,
    );
    _active[messageId] = session;
    session._timer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(session._tick()),
    );
    unawaited(session._tick());
  }

  static void stopLocal(int messageId) {
    final session = _active.remove(messageId);
    session?._dispose();
  }

  static void stopAll() {
    final ids = _active.keys.toList();
    for (final id in ids) {
      stopLocal(id);
    }
  }

  Future<void> _tick() async {
    if (_stopped) return;
    if (DateTime.now().toUtc().isAfter(expiresAt.toUtc())) {
      await stopRemote();
      return;
    }
    try {
      final pos = await getDeviceLocation();
      if (pos == null || _stopped) return;
      await ChatService.updateLiveLocation(
        conversationId: conversationId,
        messageId: messageId,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      // Best-effort; keep trying until expiry/stop.
    }
  }

  Future<void> stopRemote() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await ChatService.stopLiveLocation(
        conversationId: conversationId,
        messageId: messageId,
      );
    } catch (_) {
    } finally {
      stopLocal(messageId);
    }
  }

  void _dispose() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
