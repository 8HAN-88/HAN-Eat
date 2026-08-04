import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../app/router_keys.dart';
import '../../../services/auth_service.dart';
import '../../../services/call_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../services/user_service.dart';
import '../../../utils/api_error_parser.dart';
import '../call_kit_bridge.dart';
import 'call_screen.dart';
import 'group_call_screen.dart';
import 'incoming_call_screen.dart';
import 'minimized_call_banner.dart';

/// Global listener for incoming calls (SSE + push + CallKit) and in-app call UI host.
class CallCoordinator {
  CallCoordinator._();

  static final CallCoordinator instance = CallCoordinator._();

  StreamSubscription<UserRealtimeEvent>? _sub;
  StreamSubscription<CallEvent?>? _kitSub;
  bool _started = false;
  int? _activeCallId;
  int? _incomingDialogCallId;
  final Set<int> _kitShownIds = {};

  OverlayEntry? _callOverlay;
  Completer<void>? _callUiCompleter;
  final ValueNotifier<bool> minimized = ValueNotifier(false);
  final ValueNotifier<String> bannerTitle = ValueNotifier('Звонок');
  final ValueNotifier<String> bannerSubtitle = ValueNotifier('Идёт звонок');
  final ValueNotifier<bool> bannerIsVideo = ValueNotifier(false);
  DateTime? _hostedStartedAt;
  Timer? _bannerTick;
  Future<void> Function()? _hostedEndHandler;

  bool get hasHostedCallUi => _callOverlay != null;

  void start() {
    if (_started) return;
    _started = true;
    _sub = UserRealtimeService.instance.events.listen(_onEvent);
    if (CallKitBridge.isSupported) {
      unawaited(CallKitBridge.requestAndroidPermissions());
      _kitSub = CallKitBridge.events.listen(_onCallKitEvent);
      unawaited(_recoverActiveCallKit());
      unawaited(_syncVoipToken());
    }
  }

  Future<void> _syncVoipToken() async {
    final token = await CallKitBridge.devicePushTokenVoIP();
    if (token == null || token.isEmpty) return;
    try {
      await UserService.updateProfile(voipToken: token);
    } catch (e) {
      debugPrint('VoIP token sync failed: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _kitSub?.cancel();
    _kitSub = null;
    _started = false;
  }

  void attachActiveCall(int callId) {
    _activeCallId = callId;
  }

  void clearActiveCall(int callId) {
    if (_activeCallId == callId) _activeCallId = null;
    unawaited(CallKitBridge.end(callId));
    _kitShownIds.remove(callId);
  }

  void bindHostedEndHandler(Future<void> Function() end) {
    _hostedEndHandler = end;
  }

  void unbindHostedEndHandler(Future<void> Function() end) {
    if (_hostedEndHandler == end) _hostedEndHandler = null;
  }

  void minimizeCall() {
    if (_callOverlay == null) return;
    if (minimized.value) return;
    minimized.value = true;
    _callOverlay?.markNeedsBuild();
  }

  void expandCall() {
    if (_callOverlay == null) return;
    if (!minimized.value) return;
    minimized.value = false;
    _callOverlay?.markNeedsBuild();
  }

  Future<void> endFromBanner() async {
    final handler = _hostedEndHandler;
    if (handler != null) {
      await handler();
      return;
    }
    final id = _activeCallId;
    if (id != null) {
      try {
        await CallService.end(id);
      } catch (_) {}
    }
    closeCallUi();
  }

  void closeCallUi() {
    _bannerTick?.cancel();
    _bannerTick = null;
    _hostedStartedAt = null;
    _hostedEndHandler = null;
    final entry = _callOverlay;
    _callOverlay = null;
    minimized.value = false;
    entry?.remove();
    final c = _callUiCompleter;
    _callUiCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _hostCallUi({
    required CallSessionInfo call,
    required String title,
    required Widget child,
  }) async {
    if (_callOverlay != null) {
      expandCall();
      return _callUiCompleter?.future ?? Future<void>.value();
    }
    final overlay = hanEatRootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      final ctx = hanEatRootNavigatorKey.currentContext;
      if (ctx == null) return;
      await Navigator.of(ctx, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => child, fullscreenDialog: true),
      );
      return;
    }

    bannerTitle.value = title;
    bannerIsVideo.value = call.isVideo;
    bannerSubtitle.value = 'Идёт звонок';
    _hostedStartedAt = DateTime.now();
    minimized.value = false;
    _bannerTick?.cancel();
    _bannerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _hostedStartedAt;
      if (started == null) return;
      final d = DateTime.now().difference(started);
      final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      bannerSubtitle.value = d.inHours > 0
          ? '${d.inHours.toString().padLeft(2, '0')}:$mm:$ss'
          : '$mm:$ss';
    });

    _callUiCompleter = Completer<void>();
    _callOverlay = OverlayEntry(
      builder: (context) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            minimized,
            bannerTitle,
            bannerSubtitle,
            bannerIsVideo,
          ]),
          builder: (context, _) {
            final isMin = minimized.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Keep WebRTC State alive while minimized; IgnorePointer lets
                // taps reach the app under the overlay when the call is collapsed.
                IgnorePointer(
                  ignoring: isMin,
                  child: Offstage(
                    offstage: isMin,
                    child: child,
                  ),
                ),
                if (isMin)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: MinimizedCallBanner(
                        title: bannerTitle.value,
                        subtitle: bannerSubtitle.value,
                        isVideo: bannerIsVideo.value,
                        onExpand: expandCall,
                        onEnd: () => unawaited(endFromBanner()),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
    overlay.insert(_callOverlay!);
    await _callUiCompleter!.future;
  }

  Future<void> openOutgoing({
    required int conversationId,
    required String media,
    required BuildContext context,
    String? peerName,
  }) async {
    if (_callOverlay != null || _activeCallId != null) {
      expandCall();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала завершите текущий звонок')),
        );
      }
      return;
    }
    final call = await CallService.createCall(
      conversationId: conversationId,
      media: media,
    );
    if (CallKitBridge.isSupported) {
      await CallKitBridge.startOutgoing(
        callId: call.id,
        peerName: peerName?.trim().isNotEmpty == true
            ? peerName!.trim()
            : (call.peerName ?? 'Собеседник'),
        media: media,
      );
    }
    final title = peerName?.trim().isNotEmpty == true
        ? peerName!.trim()
        : (call.peerName?.trim().isNotEmpty == true
            ? call.peerName!.trim()
            : (call.isGroup ? 'Групповой звонок' : 'Собеседник'));
    await _hostCallUi(
      call: call,
      title: title,
      child: call.isGroup
          ? GroupCallScreen(call: call)
          : CallScreen(call: call),
    );
  }

  Future<void> openIncomingFromPush({
    required int callId,
    String? callerName,
    String? media,
  }) async {
    if (_activeCallId == callId || _incomingDialogCallId == callId) return;
    try {
      final call = await CallService.getCall(callId);
      if (call.isTerminal) return;
      await _showIncoming(call);
    } catch (e) {
      if (CallKitBridge.isSupported && !_kitShownIds.contains(callId)) {
        await CallKitBridge.showIncoming(
          callId: callId,
          callerName: callerName?.trim().isNotEmpty == true
              ? callerName!.trim()
              : 'Входящий звонок',
          media: media ?? 'voice',
          callKind: 'direct',
        );
        _kitShownIds.add(callId);
        _incomingDialogCallId = callId;
      } else {
        debugPrint('Incoming call push open failed: $e');
      }
    }
  }

  Future<void> _recoverActiveCallKit() async {
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is! List) return;
      for (final item in active) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final extra = map['extra'];
        final extraMap = extra is Map ? Map<String, dynamic>.from(extra) : null;
        final callId = CallKitBridge.callIdFromExtra(extraMap) ??
            CallKitBridge.callIdFromUuid(map['id']?.toString());
        if (callId == null || _activeCallId == callId) continue;
        final accepted = map['isAccepted'] == true || map['accepted'] == true;
        if (accepted) {
          await _answerAndOpen(callId);
        }
      }
    } catch (e) {
      debugPrint('CallKit recover failed: $e');
    }
  }

  Future<void> _onCallKitEvent(CallEvent? event) async {
    if (event == null) return;
    final extra = event.body['extra'];
    final extraMap = extra is Map ? Map<String, dynamic>.from(extra) : null;
    final callId = CallKitBridge.callIdFromExtra(extraMap) ??
        CallKitBridge.callIdFromUuid(event.body['id']?.toString());
    switch (event.event) {
      case Event.actionCallAccept:
        if (callId != null) await _answerAndOpen(callId);
        break;
      case Event.actionCallDecline:
        if (callId != null) {
          _kitShownIds.remove(callId);
          _incomingDialogCallId = null;
          try {
            await CallService.reject(callId);
          } catch (_) {}
        }
        break;
      case Event.actionCallTimeout:
      case Event.actionCallEnded:
        if (callId != null) {
          _kitShownIds.remove(callId);
          if (_incomingDialogCallId == callId) _incomingDialogCallId = null;
        }
        break;
      case Event.actionDidUpdateDevicePushTokenVoip:
        unawaited(_syncVoipToken());
        break;
      default:
        break;
    }
  }

  Future<void> _answerAndOpen(int callId) async {
    if (_activeCallId == callId || _callOverlay != null) return;
    try {
      final answered = await CallService.answer(callId);
      _incomingDialogCallId = null;
      _kitShownIds.remove(callId);
      await CallKitBridge.setConnected(callId);
      // Wait briefly for root overlay after cold start from CallKit.
      if (hanEatRootNavigatorKey.currentState?.overlay == null) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      final title = answered.peerName?.trim().isNotEmpty == true
          ? answered.peerName!.trim()
          : (answered.isGroup ? 'Групповой звонок' : 'Собеседник');
      await _hostCallUi(
        call: answered,
        title: title,
        child: answered.isGroup
            ? GroupCallScreen(call: answered)
            : CallScreen(
                call: answered,
                initialAsCallee: true,
              ),
      );
    } catch (e) {
      await CallKitBridge.end(callId);
      final navCtx = hanEatRootNavigatorKey.currentContext;
      if (navCtx != null) {
        ScaffoldMessenger.of(navCtx).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _onEvent(UserRealtimeEvent event) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null) return;
    if (event.event == 'call.invite') {
      final callId = event.callId;
      if (callId == null) return;
      if (_activeCallId != null ||
          _callOverlay != null ||
          _incomingDialogCallId == callId) {
        return;
      }
      if (event.callerId == me) return;
      final call = CallSessionInfo(
        id: callId,
        conversationId: event.conversationId ?? 0,
        callerId: event.callerId ?? event.fromUserId ?? 0,
        calleeId: me,
        kind: event.callKind ?? 'direct',
        media: event.callMedia ?? 'voice',
        status: 'ringing',
        peerId: event.callerId ?? event.fromUserId,
        peerName: event.fromName,
        peerAvatarUrl: event.fromAvatarUrl,
        isCaller: false,
        ringTimeoutSeconds: 60,
      );
      await _showIncoming(call);
      return;
    }
    if (event.event == 'call.cancelled' ||
        event.event == 'call.ended' ||
        event.event == 'call.rejected') {
      final callId = event.callId;
      if (callId != null) {
        await CallKitBridge.end(callId);
        _kitShownIds.remove(callId);
      }
      if (_incomingDialogCallId != null && callId == _incomingDialogCallId) {
        final ctx = hanEatRootNavigatorKey.currentContext;
        if (ctx != null && Navigator.of(ctx, rootNavigator: true).canPop()) {
          Navigator.of(ctx, rootNavigator: true).pop();
        }
        _incomingDialogCallId = null;
      }
    }
  }

  Future<void> _showIncoming(CallSessionInfo call) async {
    if (_incomingDialogCallId == call.id) return;
    if (_activeCallId != null || _callOverlay != null) return;

    if (CallKitBridge.isSupported) {
      if (_kitShownIds.contains(call.id)) return;
      _incomingDialogCallId = call.id;
      _kitShownIds.add(call.id);
      final timeoutMs =
          (call.ringTimeoutSeconds > 0 ? call.ringTimeoutSeconds : 60) * 1000;
      await CallKitBridge.showIncoming(
        callId: call.id,
        callerName: call.peerName?.trim().isNotEmpty == true
            ? call.peerName!.trim()
            : (call.isGroup ? 'Групповой звонок' : 'Входящий звонок'),
        avatarUrl: call.peerAvatarUrl,
        media: call.media,
        callKind: call.kind,
        conversationId: call.conversationId,
        durationMs: timeoutMs,
      );
      return;
    }

    final ctx = hanEatRootNavigatorKey.currentContext;
    if (ctx == null) return;
    _incomingDialogCallId = call.id;
    final timeout = Duration(
      seconds: call.ringTimeoutSeconds > 0 ? call.ringTimeoutSeconds : 60,
    );
    final accepted = await Navigator.of(ctx, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => IncomingCallScreen(call: call, timeout: timeout),
        fullscreenDialog: true,
      ),
    );
    _incomingDialogCallId = null;
    if (accepted == true) {
      await _answerAndOpen(call.id);
    } else if (accepted == false) {
      try {
        await CallService.reject(call.id);
      } catch (_) {}
    }
  }
}
