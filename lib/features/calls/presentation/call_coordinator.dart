import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/router_keys.dart';
import '../../../services/auth_service.dart';
import '../../../services/call_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../utils/api_error_parser.dart';
import 'call_screen.dart';

/// Global listener for incoming 1:1 calls (SSE + push).
class CallCoordinator {
  CallCoordinator._();

  static final CallCoordinator instance = CallCoordinator._();

  StreamSubscription<UserRealtimeEvent>? _sub;
  bool _started = false;
  int? _activeCallId;
  int? _incomingDialogCallId;

  void start() {
    if (_started) return;
    _started = true;
    _sub = UserRealtimeService.instance.events.listen(_onEvent);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void attachActiveCall(int callId) {
    _activeCallId = callId;
  }

  void clearActiveCall(int callId) {
    if (_activeCallId == callId) _activeCallId = null;
  }

  Future<void> openOutgoing({
    required int conversationId,
    required String media,
    required BuildContext context,
  }) async {
    final call = await CallService.createCall(
      conversationId: conversationId,
      media: media,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(call: call),
        fullscreenDialog: true,
      ),
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
      debugPrint('Incoming call push open failed: $e');
    }
  }

  Future<void> _onEvent(UserRealtimeEvent event) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null) return;
    if (event.event == 'call.invite') {
      final callId = event.callId;
      if (callId == null) return;
      if (_activeCallId != null || _incomingDialogCallId == callId) return;
      // Ignore invites we ourselves created.
      if (event.callerId == me) return;
      final call = CallSessionInfo(
        id: callId,
        conversationId: event.conversationId ?? 0,
        callerId: event.callerId ?? event.fromUserId ?? 0,
        calleeId: me,
        media: event.callMedia ?? 'voice',
        status: 'ringing',
        peerId: event.callerId ?? event.fromUserId,
        peerName: event.fromName,
        peerAvatarUrl: event.fromAvatarUrl,
        isCaller: false,
      );
      await _showIncoming(call);
      return;
    }
    if (event.event == 'call.cancelled' ||
        event.event == 'call.ended' ||
        event.event == 'call.rejected') {
      if (_incomingDialogCallId != null &&
          event.callId == _incomingDialogCallId) {
        final ctx = hanEatRootNavigatorKey.currentContext;
        if (ctx != null && Navigator.of(ctx).canPop()) {
          // Close incoming dialog if still open.
          Navigator.of(ctx, rootNavigator: true).pop();
        }
        _incomingDialogCallId = null;
      }
    }
  }

  Future<void> _showIncoming(CallSessionInfo call) async {
    final ctx = hanEatRootNavigatorKey.currentContext;
    if (ctx == null) return;
    if (_incomingDialogCallId == call.id) return;
    _incomingDialogCallId = call.id;
    final peerName = call.peerName?.trim().isNotEmpty == true
        ? call.peerName!.trim()
        : 'Входящий звонок';
    final accepted = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(call.isVideo ? 'Видеозвонок' : 'Звонок'),
          content: Text('$peerName звонит вам'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Отклонить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Ответить'),
            ),
          ],
        );
      },
    );
    _incomingDialogCallId = null;
    if (accepted == true) {
      try {
        final answered = await CallService.answer(call.id);
        final navCtx = hanEatRootNavigatorKey.currentContext;
        if (navCtx == null) return;
        await Navigator.of(navCtx).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              call: answered,
              initialAsCallee: true,
            ),
            fullscreenDialog: true,
          ),
        );
      } catch (e) {
        final navCtx = hanEatRootNavigatorKey.currentContext;
        if (navCtx != null) {
          ScaffoldMessenger.of(navCtx).showSnackBar(
            SnackBar(content: Text(userVisibleError(e))),
          );
        }
      }
    } else if (accepted == false) {
      try {
        await CallService.reject(call.id);
      } catch (_) {}
    }
  }
}
