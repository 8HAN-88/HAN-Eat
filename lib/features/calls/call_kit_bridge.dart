import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Native CallKit (iOS) / full-screen incoming (Android) bridge.
class CallKitBridge {
  CallKitBridge._();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String uuidForCallId(int callId) {
    final hex = callId.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$hex';
  }

  static int? callIdFromUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    final parts = uuid.split('-');
    if (parts.length != 5) return null;
    return int.tryParse(parts.last, radix: 16);
  }

  static int? callIdFromExtra(Map? extra) {
    if (extra == null) return null;
    final raw = extra['call_id'] ?? extra['callId'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  static Future<void> showIncoming({
    required int callId,
    required String callerName,
    String? avatarUrl,
    String media = 'voice',
    String callKind = 'direct',
    int? conversationId,
    int durationMs = 60000,
  }) async {
    if (!isSupported) return;
    final params = CallKitParams(
      id: uuidForCallId(callId),
      nameCaller: callerName,
      appName: 'HanWe',
      avatar: avatarUrl,
      handle: callerName,
      type: media == 'video' ? 1 : 0,
      textAccept: 'Ответить',
      textDecline: 'Отклонить',
      duration: durationMs,
      extra: <String, dynamic>{
        'call_id': callId,
        'media': media,
        'call_kind': callKind,
        if (conversationId != null) 'conversation_id': conversationId,
        'caller_name': callerName,
      },
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Пропущенный звонок',
        callbackText: 'Перезвонить',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B1220',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Входящие звонки',
        missedCallNotificationChannelName: 'Пропущенные звонки',
        isShowCallID: false,
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: media == 'video',
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Used from FCM background isolate (no Navigator).
  static Future<void> showFromPushData(Map<String, dynamic> data) async {
    if (!isSupported) return;
    final type = data['type']?.toString() ?? '';
    final route = data['route']?.toString();
    if (route != 'call' && type != 'call.incoming') return;
    final callId = int.tryParse('${data['call_id'] ?? data['callId'] ?? ''}');
    if (callId == null) return;
    final name = (data['caller_name'] ?? data['title'] ?? 'Звонок').toString();
    final media = (data['media'] ?? 'voice').toString();
    final callKind = (data['call_kind'] ?? data['callKind'] ?? 'direct').toString();
    final conversationId =
        int.tryParse('${data['conversation_id'] ?? data['conversationId'] ?? ''}');
    await showIncoming(
      callId: callId,
      callerName: name,
      media: media,
      callKind: callKind,
      conversationId: conversationId,
      avatarUrl: data['caller_avatar']?.toString() ??
          data['from_avatar_url']?.toString(),
    );
  }

  static Future<void> startOutgoing({
    required int callId,
    required String peerName,
    String media = 'voice',
  }) async {
    if (!isSupported) return;
    final params = CallKitParams(
      id: uuidForCallId(callId),
      nameCaller: peerName,
      appName: 'HanWe',
      handle: peerName,
      type: media == 'video' ? 1 : 0,
      extra: <String, dynamic>{
        'call_id': callId,
        'media': media,
      },
      ios: const IOSParams(handleType: 'generic'),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowCallID: false,
      ),
    );
    await FlutterCallkitIncoming.startCall(params);
  }

  static Future<void> setConnected(int callId) async {
    if (!isSupported) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(uuidForCallId(callId));
    } catch (_) {}
  }

  static Future<void> end(int callId) async {
    if (!isSupported) return;
    try {
      await FlutterCallkitIncoming.endCall(uuidForCallId(callId));
    } catch (_) {}
  }

  static Future<void> endAll() async {
    if (!isSupported) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  static Stream<CallEvent?> get events => FlutterCallkitIncoming.onEvent;

  static Future<void> requestAndroidPermissions() async {
    if (!isSupported || !Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Уведомления о звонках',
        'rationaleMessagePermission':
            'Нужны, чтобы показывать входящие звонки на экране блокировки.',
        'postNotificationMessageRequired':
            'Разрешите уведомления в настройках, чтобы принимать звонки.',
      });
    } catch (_) {}
    try {
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (can == false) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {}
  }

  static Future<String?> devicePushTokenVoIP() async {
    if (!isSupported || !Platform.isIOS) return null;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token == null) return null;
      final s = token.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }
}
