import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/call_service.dart';
import '../../services/user_realtime_service.dart';

/// Helpers for mute/camera sync and a lightweight link-quality hint.
class CallMediaControls {
  CallMediaControls._();

  static Future<void> publishMute(
    int callId, {
    required bool muted,
    int? toUserId,
  }) async {
    try {
      await CallService.signal(
        callId,
        kind: 'mute',
        toUserId: toUserId,
        payload: {'muted': muted},
      );
    } catch (_) {}
  }

  static Future<void> publishCamera(
    int callId, {
    required bool off,
    int? toUserId,
  }) async {
    try {
      await CallService.signal(
        callId,
        kind: 'camera',
        toUserId: toUserId,
        payload: {'off': off},
      );
    } catch (_) {}
  }

  static bool? muteFromEvent(UserRealtimeEvent event) {
    if (event.signalKind != 'mute') return null;
    final payload = event.signalPayload;
    if (payload == null) return null;
    final v = payload['muted'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return null;
  }

  static bool? cameraOffFromEvent(UserRealtimeEvent event) {
    if (event.signalKind != 'camera') return null;
    final payload = event.signalPayload;
    if (payload == null) return null;
    final v = payload['off'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return null;
  }

  /// Returns true when inbound packet loss looks high enough to warn the user.
  static Future<bool> isWeakLink(RTCPeerConnection? pc) async {
    if (pc == null) return false;
    try {
      final reports = await pc.getStats();
      var lost = 0;
      var received = 0;
      for (final report in reports) {
        final values = report.values;
        final type = report.type.toLowerCase();
        if (type != 'inbound-rtp' && type != 'remote-inbound-rtp') continue;
        final media =
            (values['kind'] ?? values['mediaType'] ?? '').toString().toLowerCase();
        if (media.isNotEmpty && media != 'audio' && media != 'video') continue;
        final pl = values['packetsLost'];
        final pr = values['packetsReceived'] ?? values['packetsSent'];
        if (pl is num) lost += pl.round();
        if (pr is num) received += pr.round();
      }
      final total = lost + received;
      if (total < 40) return false;
      return lost / total >= 0.08;
    } catch (_) {
      return false;
    }
  }
}
