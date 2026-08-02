import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/call_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../utils/api_error_parser.dart';
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
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<UserRealtimeEvent>? _sub;
  final List<RTCIceCandidate> _pendingRemoteIce = [];

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _initializing = true;
  bool _remoteReady = false;
  bool _ending = false;
  bool _offerSent = false;
  String _status = 'Подключение...';
  DateTime? _callStartedAt;
  Timer? _ticker;
  late CallSessionInfo _call;

  bool get _isVideo => _call.isVideo;

  @override
  void initState() {
    super.initState();
    _call = widget.call;
    CallCoordinator.instance.attachActiveCall(_call.id);
    _sub = UserRealtimeService.instance.events.listen(_onRealtime);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

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
      await Helper.setSpeakerphoneOn(_isVideo ? true : _speakerOn);
      _speakerOn = _isVideo ? true : _speakerOn;

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
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      };
      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _status = 'Идёт звонок';
            _callStartedAt ??= DateTime.now();
          });
          _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _status = 'Соединение прервано');
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

      // Caller waits for answer then creates offer.
      // Callee already answered before opening this screen (or answers here).
      if (!_call.isCaller && _call.isRinging) {
        final answered = await CallService.answer(_call.id);
        if (!mounted) return;
        setState(() {
          _call = answered;
          _status = 'Соединение...';
        });
      } else if (_call.isCaller) {
        // Refresh in case answer event arrived before we subscribed.
        final fresh = await CallService.getCall(_call.id);
        if (!mounted) return;
        setState(() {
          _call = fresh;
          _status = fresh.isActive ? 'Соединение...' : 'Вызов...';
        });
        if (fresh.isActive) {
          await _createAndSendOffer();
        }
      }
    } catch (e) {
      await _failAndClose(userVisibleError(e, fallback: 'Не удалось начать звонок'));
    }
  }

  Future<void> _failAndClose(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _cleanup(notifyServer: true);
    if (mounted) Navigator.of(context).pop();
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
        await _cleanup(notifyServer: false);
        if (mounted) Navigator.of(context).pop();
        break;
    }
  }

  Future<void> _handleSignal(UserRealtimeEvent event) async {
    final kind = event.signalKind;
    final payload = event.signalPayload;
    if (kind == null || payload == null || _pc == null) return;
    try {
      if (kind == 'offer') {
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
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    final next = !_micMuted;
    track.enabled = !next;
    if (!mounted) return;
    setState(() => _micMuted = next);
  }

  Future<void> _toggleCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    final next = !_cameraOff;
    track.enabled = !next;
    if (!mounted) return;
    setState(() => _cameraOff = next);
  }

  Future<void> _switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    await Helper.switchCamera(track);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    await Helper.setSpeakerphoneOn(next);
    if (!mounted) return;
    setState(() => _speakerOn = next);
  }

  Future<void> _endCall() async {
    if (_ending) return;
    await _cleanup(notifyServer: true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup({required bool notifyServer}) async {
    if (_ending) return;
    _ending = true;
    _ticker?.cancel();
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
    _ticker?.cancel();
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
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerName = _call.peerName?.trim().isNotEmpty == true
        ? _call.peerName!.trim()
        : 'Собеседник';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _endCall,
                  ),
                  const Spacer(),
                  Text(
                    peerName,
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
                            ? (_remoteReady
                                ? RTCVideoView(
                                    _remoteRenderer,
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitCover,
                                  )
                                : Container(
                                    color: Colors.grey.shade900,
                                    alignment: Alignment.center,
                                    child: Text(
                                      peerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    ),
                                  ))
                            : Container(
                                color: Colors.grey.shade900,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 48,
                                      child: Text(
                                        peerName.isNotEmpty
                                            ? peerName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(fontSize: 36),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      peerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
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
                            Text(
                              _status,
                              style: const TextStyle(color: Colors.white),
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
