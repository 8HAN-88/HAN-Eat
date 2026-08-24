import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/router_keys.dart';
import '../../../services/call_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../widgets/highlighted_text.dart';
import '../call_kit_bridge.dart';
import '../call_media_controls.dart';
import 'call_coordinator.dart';

/// Working 1:1 WebRTC voice/video call (Telegram-like).
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.call,
    this.initialAsCallee = false,
  });

  final CallSessionInfo call;
  final bool initialAsCallee;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<UserRealtimeEvent>? _sub;
  final List<RTCIceCandidate> _pendingRemoteIce = [];

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _remoteMuted = false;
  bool _remoteCameraOff = false;
  bool _weakLink = false;
  bool _initializing = true;
  bool _remoteReady = false;
  bool _ending = false;
  bool _offerSent = false;
  bool _iceRestartAttempted = false;
  String _status = 'Подключение...';
  DateTime? _callStartedAt;
  Timer? _ticker;
  Timer? _ringTimer;
  Timer? _disconnectTimer;
  Timer? _qualityTimer;
  late CallSessionInfo _call;
  late final Future<void> Function() _boundEnd = _endCall;
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  bool get _isVideo => _call.isVideo;

  @override
  void initState() {
    super.initState();
    _call = widget.call;
    _speakerOn = _isVideo;
    CallCoordinator.instance.attachActiveCall(_call.id);
    CallCoordinator.instance.bindHostedEndHandler(_boundEnd);
    _sub = UserRealtimeService.instance.events.listen(_onRealtime);
    unawaited(WakelockPlus.enable());
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    try {
      final ice = await CallService.fetchIceConfig();
      _iceServers = {'iceServers': ice.iceServers};
      if (_call.isCaller && _call.isRinging) {
        final seconds = _call.ringTimeoutSeconds > 0
            ? _call.ringTimeoutSeconds
            : ice.ringTimeoutSeconds;
        _ringTimer = Timer(Duration(seconds: seconds), () async {
          if (_ending || !_call.isRinging) return;
          setState(() => _status = 'Нет ответа');
          try {
            await CallService.cancel(_call.id);
          } catch (_) {}
          await _leaveUi(notifyServer: false);
        });
      }
    } catch (_) {}

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      await _failAndClose('Нужен доступ к микрофону');
      return;
    }
    if (_isVideo) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        await _failAndClose('Нужен доступ к камере');
        return;
      }
    }
    // Optional Bluetooth route permission (Android 12+).
    try {
      await Permission.bluetoothConnect.request();
    } catch (_) {}

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': _isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30},
              }
            : false,
      });
      _localRenderer.srcObject = _localStream;
      await Helper.setSpeakerphoneOn(_speakerOn);

      _pc = await createPeerConnection(_iceServers);
      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
        unawaited(
          CallService.signal(
            _call.id,
            kind: 'ice',
            payload: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          ),
        );
      };
      _pc!.onTrack = (event) {
        if (event.streams.isEmpty) return;
        _remoteRenderer.srcObject = event.streams.first;
        if (!mounted) return;
        setState(() {
          _remoteReady = true;
          _status = 'Идёт звонок';
          _callStartedAt ??= DateTime.now();
        });
        _startTicker();
      };
      _pc!.onConnectionState = (state) {
        if (!mounted || _ending) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
          unawaited(CallKitBridge.setConnected(_call.id));
          setState(() {
            _status = 'Идёт звонок';
            _callStartedAt ??= DateTime.now();
          });
          _startTicker();
          unawaited(CallMediaControls.publishMute(_call.id, muted: _micMuted));
          if (_isVideo) {
            unawaited(
              CallMediaControls.publishCamera(_call.id, off: _cameraOff),
            );
          }
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _status = 'Соединение прервано');
          _disconnectTimer ??= Timer(const Duration(seconds: 6), () {
            unawaited(_handleDisconnectRecovery());
          });
        }
      };

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = widget.initialAsCallee || !_call.isCaller
            ? 'Соединение...'
            : 'Вызов...';
      });

      if (!_call.isCaller && _call.isRinging) {
        final answered = await CallService.answer(_call.id);
        if (!mounted) return;
        setState(() {
          _call = answered;
          _status = 'Соединение...';
        });
      } else if (_call.isCaller) {
        final fresh = await CallService.getCall(_call.id);
        if (!mounted) return;
        setState(() {
          _call = fresh;
          _status = fresh.isActive ? 'Соединение...' : 'Вызов...';
        });
        if (fresh.isActive) {
          _ringTimer?.cancel();
          await _createAndSendOffer();
        }
      }
    } catch (e) {
      await _failAndClose(userVisibleError(e, fallback: 'Не удалось начать звонок'));
    }
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _qualityTimer ??= Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_refreshLinkQuality());
    });
  }

  Future<void> _refreshLinkQuality() async {
    if (_ending || !mounted) return;
    final weak = await CallMediaControls.isWeakLink(_pc);
    if (!mounted || weak == _weakLink) return;
    setState(() => _weakLink = weak);
  }

  Future<void> _handleDisconnectRecovery() async {
    if (_ending || !mounted || _pc == null) return;
    if (!_iceRestartAttempted) {
      _iceRestartAttempted = true;
      setState(() => _status = 'Переподключение...');
      try {
        await _pc!.restartIce();
        final offer = await _pc!.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': _isVideo ? 1 : 0,
        });
        await _pc!.setLocalDescription(offer);
        await CallService.signal(
          _call.id,
          kind: 'renegotiate',
          payload: {
            'sdp': offer.sdp,
            'type': offer.type,
          },
        );
        _disconnectTimer = Timer(const Duration(seconds: 8), () {
          unawaited(_endCall());
        });
        return;
      } catch (e) {
        debugPrint('ICE restart failed: $e');
      }
    }
    await _endCall();
  }

  Future<void> _failAndClose(String message) async {
    final ctx = hanEatRootNavigatorKey.currentContext ?? context;
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
    }
    await _leaveUi(notifyServer: true);
  }

  Future<void> _leaveUi({required bool notifyServer}) async {
    await _cleanup(notifyServer: notifyServer);
    if (CallCoordinator.instance.hasHostedCallUi) {
      CallCoordinator.instance.closeCallUi();
    } else if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _createAndSendOffer() async {
    if (_offerSent || _pc == null) return;
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideo ? 1 : 0,
    });
    await _pc!.setLocalDescription(offer);
    _offerSent = true;
    await CallService.signal(
      _call.id,
      kind: 'offer',
      payload: {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    );
  }

  Future<void> _onRealtime(UserRealtimeEvent event) async {
    if (event.callId != null && event.callId != _call.id) return;
    switch (event.event) {
      case 'call.answered':
        if (_call.isCaller && !_offerSent) {
          _ringTimer?.cancel();
          setState(() {
            _status = 'Соединение...';
            _call = CallSessionInfo(
              id: _call.id,
              conversationId: _call.conversationId,
              callerId: _call.callerId,
              calleeId: _call.calleeId,
              media: _call.media,
              status: 'active',
              peerId: _call.peerId,
              peerName: _call.peerName,
              peerAvatarUrl: _call.peerAvatarUrl,
              isCaller: _call.isCaller,
              ringTimeoutSeconds: _call.ringTimeoutSeconds,
            );
          });
          await _createAndSendOffer();
        }
        break;
      case 'call.signal':
        await _handleSignal(event);
        break;
      case 'call.rejected':
      case 'call.cancelled':
      case 'call.ended':
        if (_ending) return;
        setState(() => _status = 'Звонок завершён');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _leaveUi(notifyServer: false);
        break;
    }
  }

  Future<void> _handleSignal(UserRealtimeEvent event) async {
    final kind = event.signalKind;
    final mute = CallMediaControls.muteFromEvent(event);
    if (mute != null) {
      if (mounted) setState(() => _remoteMuted = mute);
      return;
    }
    final camOff = CallMediaControls.cameraOffFromEvent(event);
    if (camOff != null) {
      if (mounted) setState(() => _remoteCameraOff = camOff);
      return;
    }
    final payload = event.signalPayload;
    if (kind == null || payload == null || _pc == null) return;
    try {
      if (kind == 'offer' || kind == 'renegotiate') {
        final sdp = payload['sdp'] as String?;
        final type = payload['type'] as String? ?? 'offer';
        if (sdp == null) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
        await _flushPendingIce();
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await CallService.signal(
          _call.id,
          kind: 'answer',
          payload: {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        );
      } else if (kind == 'answer') {
        final sdp = payload['sdp'] as String?;
        final type = payload['type'] as String? ?? 'answer';
        if (sdp == null) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
        await _flushPendingIce();
      } else if (kind == 'ice') {
        final candidate = payload['candidate'] as String?;
        if (candidate == null || candidate.isEmpty) return;
        final ice = RTCIceCandidate(
          candidate,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        );
        final remote = await _pc!.getRemoteDescription();
        if (remote == null) {
          _pendingRemoteIce.add(ice);
        } else {
          await _pc!.addCandidate(ice);
        }
      }
    } catch (e) {
      debugPrint('Call signal error: $e');
    }
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null || _pendingRemoteIce.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteIce);
    _pendingRemoteIce.clear();
    for (final ice in pending) {
      try {
        await _pc!.addCandidate(ice);
      } catch (_) {}
    }
  }

  Future<void> _toggleMic() async {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !_micMuted;
    tracks.first.enabled = !next;
    if (!mounted) return;
    setState(() => _micMuted = next);
    unawaited(CallMediaControls.publishMute(_call.id, muted: next));
  }

  Future<void> _toggleCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !_cameraOff;
    tracks.first.enabled = !next;
    if (!mounted) return;
    setState(() => _cameraOff = next);
    unawaited(CallMediaControls.publishCamera(_call.id, off: next));
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сменить камеру'))),
      );
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
      if (!mounted) return;
      setState(() => _speakerOn = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось переключить звук'))),
      );
    }
  }

  Future<void> _endCall() async {
    if (_ending) return;
    await _leaveUi(notifyServer: true);
  }

  Future<void> _cleanup({required bool notifyServer}) async {
    if (_ending) return;
    _ending = true;
    _ticker?.cancel();
    _ringTimer?.cancel();
    _disconnectTimer?.cancel();
    _qualityTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    if (notifyServer && !_call.isTerminal) {
      try {
        await CallService.end(_call.id);
      } catch (_) {}
    }
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    CallCoordinator.instance.clearActiveCall(_call.id);
    await CallKitBridge.end(_call.id);
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  String get _durationLabel {
    final started = _callStartedAt;
    if (started == null) return '00:00';
    final d = DateTime.now().difference(started);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  void dispose() {
    CallCoordinator.instance.unbindHostedEndHandler(_boundEnd);
    _ticker?.cancel();
    _ringTimer?.cancel();
    _disconnectTimer?.cancel();
    _qualityTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    if (!_ending) {
      _ending = true;
      if (!_call.isTerminal) {
        unawaited(CallService.end(_call.id).catchError((_) => _call));
      }
      unawaited(_pc?.close() ?? Future<void>.value());
      for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        unawaited(t.stop());
      }
      unawaited(_localStream?.dispose() ?? Future<void>.value());
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      unawaited(_localRenderer.dispose());
      unawaited(_remoteRenderer.dispose());
      CallCoordinator.instance.clearActiveCall(_call.id);
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerName = _call.peerName?.trim().isNotEmpty == true
        ? _call.peerName!.trim()
        : 'Собеседник';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) CallCoordinator.instance.minimizeCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Свернуть',
                      onPressed: CallCoordinator.instance.minimizeCall,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    ),
                    const Spacer(),
                    HighlightedText(
                      text: peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _initializing
                          ? const Center(child: CircularProgressIndicator())
                          : _isVideo
                              ? (_remoteReady && !_remoteCameraOff
                                  ? RTCVideoView(
                                      _remoteRenderer,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                    )
                                  : _peerPlaceholder(peerName))
                              : _peerPlaceholder(peerName),
                    ),
                    if (_remoteMuted && !_initializing)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _pill(
                          icon: Icons.mic_off,
                          label: 'Микрофон выкл.',
                        ),
                      ),
                    if (_weakLink && !_initializing)
                      Positioned(
                        top: 16,
                        right: _isVideo ? 140 : 16,
                        child: _pill(
                          icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
                          label: 'Плохая связь',
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    if (_isVideo && !_initializing)
                      Positioned(
                        right: 16,
                        top: 16,
                        width: 110,
                        height: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _cameraOff
                              ? Container(color: Colors.black54)
                              : RTCVideoView(
                                  _localRenderer,
                                  mirror: true,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                        ),
                      ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _weakLink ? 'Плохая связь' : _status,
                                  style: TextStyle(
                                    color: _weakLink
                                        ? const Color(0xFFFFD38A)
                                        : Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _durationLabel,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                color: Colors.black87,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: _micMuted ? Icons.mic_off : Icons.mic,
                      label: 'Микрофон',
                      onPressed: _toggleMic,
                    ),
                    if (_isVideo)
                      _CallButton(
                        icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                        label: 'Видео',
                        onPressed: _toggleCamera,
                      ),
                    if (_isVideo)
                      _CallButton(
                        icon: Icons.cameraswitch_outlined,
                        label: 'Камера',
                        onPressed: _switchCamera,
                      ),
                    _CallButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                      label: 'Звук',
                      onPressed: _toggleSpeaker,
                    ),
                    _CallButton(
                      icon: Icons.call_end,
                      label: 'Завершить',
                      color: Colors.red,
                      onPressed: _endCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peerPlaceholder(String peerName) {
    return Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 48,
            child: Text(
              avatarLetterWithCustomEmoji(peerName),
              style: const TextStyle(fontSize: 36),
            ),
          ),
          const SizedBox(height: 16),
          HighlightedText(
            text: peerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_remoteMuted) ...[
            const SizedBox(height: 10),
            const Text(
              'Микрофон выключен',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          if (_isVideo && _remoteCameraOff) ...[
            const SizedBox(height: 6),
            const Text(
              'Камера выключена',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    Color color = const Color(0xCC111827),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color ?? Colors.white, size: 28),
          onPressed: onPressed,
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
