import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/router_keys.dart';
import '../../../services/auth_service.dart';
import '../../../services/call_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../utils/api_error_parser.dart';
import '../call_kit_bridge.dart';
import '../call_media_controls.dart';
import 'call_coordinator.dart';

/// Small-group mesh call (up to 4 peers) using 1:1 PCs between members.
class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, required this.call});

  final CallSessionInfo call;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<int, RTCPeerConnection> _pcs = {};
  final Map<int, RTCVideoRenderer> _remotes = {};
  final Map<int, List<RTCIceCandidate>> _pendingIce = {};
  MediaStream? _localStream;
  StreamSubscription<UserRealtimeEvent>? _sub;
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };
  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _ending = false;
  bool _initializing = true;
  bool _weakLink = false;
  String _status = 'Подключение...';
  DateTime? _callStartedAt;
  Timer? _ticker;
  Timer? _qualityTimer;
  final Map<int, bool> _remoteMuted = {};
  final Map<int, bool> _remoteCameraOff = {};
  late CallSessionInfo _call;
  late final Future<void> Function() _boundEnd = _hangup;

  int? get _me => AuthService.instance.currentUser?.id;
  bool get _isVideo => _call.isVideo;

  String get _durationLabel {
    if (_callStartedAt == null) return '';
    final sec = DateTime.now().difference(_callStartedAt!).inSeconds;
    final mm = (sec ~/ 60).toString().padLeft(2, '0');
    final ss = (sec % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void initState() {
    super.initState();
    _call = widget.call;
    CallCoordinator.instance.attachActiveCall(_call.id);
    CallCoordinator.instance.bindHostedEndHandler(_boundEnd);
    _sub = UserRealtimeService.instance.events.listen(_onRealtime);
    unawaited(WakelockPlus.enable());
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _localRenderer.initialize();
    try {
      final ice = await CallService.fetchIceConfig();
      _iceServers = {'iceServers': ice.iceServers};
    } catch (_) {}

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      await _fail('Нужен доступ к микрофону');
      return;
    }
    if (_isVideo) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        await _fail('Нужен доступ к камере');
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
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
      _localRenderer.srcObject = _localStream;
      await Helper.setSpeakerphoneOn(_speakerOn);

      // Host is already joined; invitees answer via CallCoordinator before open.
      if (!_call.isCaller && _call.status != 'active') {
        _call = await CallService.answer(_call.id);
      } else {
        _call = await CallService.getCall(_call.id);
      }

      final peers = _call.participants
          .where((p) => p.isJoined && p.userId != _me)
          .map((p) => p.userId)
          .toList();
      for (final peerId in peers) {
        // Deterministic offerer: lower user id creates the offer.
        if ((_me ?? 0) < peerId) {
          await _ensurePc(peerId, createOffer: true);
        } else {
          await _ensurePc(peerId, createOffer: false);
        }
      }

      if (!mounted) return;
      _callStartedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _qualityTimer?.cancel();
      _qualityTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(_refreshLinkQuality());
      });
      // Publish current media state so late joiners sync after answer.
      unawaited(CallMediaControls.publishMute(_call.id, muted: _micMuted));
      if (_isVideo) {
        unawaited(CallMediaControls.publishCamera(_call.id, off: _cameraOff));
      }
      setState(() {
        _initializing = false;
        _status = 'Групповой звонок';
      });
    } catch (e) {
      await _fail(userVisibleError(e, fallback: 'Не удалось начать звонок'));
    }
  }

  Future<RTCPeerConnection> _ensurePc(int peerId, {required bool createOffer}) async {
    final existing = _pcs[peerId];
    if (existing != null) return existing;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remotes[peerId] = renderer;

    final pc = await createPeerConnection(_iceServers);
    _pcs[peerId] = pc;
    _pendingIce[peerId] = [];

    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      unawaited(
        CallService.signal(
          _call.id,
          kind: 'ice',
          toUserId: peerId,
          payload: {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        ),
      );
    };
    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remotes[peerId]?.srcObject = event.streams.first;
      if (mounted) setState(() {});
    };

    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(track, _localStream!);
    }

    if (createOffer) {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _isVideo ? 1 : 0,
      });
      await pc.setLocalDescription(offer);
      await CallService.signal(
        _call.id,
        kind: 'offer',
        toUserId: peerId,
        payload: {'sdp': offer.sdp, 'type': offer.type},
      );
    }
    if (mounted) setState(() {});
    return pc;
  }

  Future<void> _onRealtime(UserRealtimeEvent event) async {
    if (event.callId != null && event.callId != _call.id) return;
    switch (event.event) {
      case 'call.participant_joined':
        final joinedId = event.userId ?? event.fromUserId;
        if (joinedId == null || joinedId == _me) return;
        try {
          _call = await CallService.getCall(_call.id);
        } catch (_) {}
        if ((_me ?? 0) < joinedId) {
          await _ensurePc(joinedId, createOffer: true);
        } else {
          await _ensurePc(joinedId, createOffer: false);
        }
        // Sync media state for the newcomer.
        unawaited(CallMediaControls.publishMute(_call.id, muted: _micMuted));
        if (_isVideo) {
          unawaited(CallMediaControls.publishCamera(_call.id, off: _cameraOff));
        }
        break;
      case 'call.signal':
        await _handleSignal(event);
        break;
      case 'call.participant_left':
        final leftId = event.userId ?? event.fromUserId;
        if (leftId != null) await _dropPeer(leftId);
        break;
      case 'call.ended':
      case 'call.cancelled':
      case 'call.rejected':
        await _leaveUi(notifyServer: false);
        break;
    }
  }

  Future<void> _refreshLinkQuality() async {
    if (_ending || !mounted || _pcs.isEmpty) return;
    var weak = false;
    for (final pc in _pcs.values) {
      if (await CallMediaControls.isWeakLink(pc)) {
        weak = true;
        break;
      }
    }
    if (!mounted || weak == _weakLink) return;
    setState(() => _weakLink = weak);
  }

  Future<void> _handleSignal(UserRealtimeEvent event) async {
    final from = event.fromUserId;
    final mute = CallMediaControls.muteFromEvent(event);
    if (mute != null && from != null) {
      if (mounted) setState(() => _remoteMuted[from] = mute);
      return;
    }
    final camOff = CallMediaControls.cameraOffFromEvent(event);
    if (camOff != null && from != null) {
      if (mounted) setState(() => _remoteCameraOff[from] = camOff);
      return;
    }
    final kind = event.signalKind;
    final payload = event.signalPayload;
    if (from == null || kind == null || payload == null) return;
    final pc = await _ensurePc(from, createOffer: false);
    try {
      if (kind == 'offer' || kind == 'renegotiate') {
        final sdp = payload['sdp'] as String?;
        if (sdp == null) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(sdp, payload['type'] as String? ?? 'offer'),
        );
        await _flushIce(from);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await CallService.signal(
          _call.id,
          kind: 'answer',
          toUserId: from,
          payload: {'sdp': answer.sdp, 'type': answer.type},
        );
      } else if (kind == 'answer') {
        final sdp = payload['sdp'] as String?;
        if (sdp == null) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(sdp, payload['type'] as String? ?? 'answer'),
        );
        await _flushIce(from);
      } else if (kind == 'ice') {
        final candidate = payload['candidate'] as String?;
        if (candidate == null || candidate.isEmpty) return;
        final ice = RTCIceCandidate(
          candidate,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        );
        final remote = await pc.getRemoteDescription();
        if (remote == null) {
          _pendingIce[from]?.add(ice);
        } else {
          await pc.addCandidate(ice);
        }
      }
    } catch (e) {
      debugPrint('Group signal error: $e');
    }
  }

  Future<void> _flushIce(int peerId) async {
    final pc = _pcs[peerId];
    final pending = _pendingIce[peerId];
    if (pc == null || pending == null || pending.isEmpty) return;
    final copy = List<RTCIceCandidate>.from(pending);
    pending.clear();
    for (final ice in copy) {
      try {
        await pc.addCandidate(ice);
      } catch (_) {}
    }
  }

  Future<void> _dropPeer(int peerId) async {
    try {
      await _pcs[peerId]?.close();
    } catch (_) {}
    _pcs.remove(peerId);
    final r = _remotes.remove(peerId);
    r?.srcObject = null;
    await r?.dispose();
    _pendingIce.remove(peerId);
    if (mounted) setState(() {});
  }

  Future<void> _fail(String msg) async {
    final ctx = hanEatRootNavigatorKey.currentContext ?? context;
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
    await _leaveUi(notifyServer: true);
  }

  Future<void> _hangup() async {
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

  Future<void> _cleanup({required bool notifyServer}) async {
    if (_ending) return;
    _ending = true;
    _ticker?.cancel();
    _ticker = null;
    _qualityTimer?.cancel();
    _qualityTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (notifyServer && !_call.isTerminal) {
      try {
        await CallService.end(_call.id);
      } catch (_) {}
    }
    for (final id in _pcs.keys.toList()) {
      await _dropPeer(id);
    }
    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;
    await _localRenderer.dispose();
    CallCoordinator.instance.clearActiveCall(_call.id);
    await CallKitBridge.end(_call.id);
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> _toggleMic() async {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !_micMuted;
    tracks.first.enabled = !next;
    setState(() => _micMuted = next);
    unawaited(CallMediaControls.publishMute(_call.id, muted: next));
  }

  Future<void> _toggleCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !_cameraOff;
    tracks.first.enabled = !next;
    setState(() => _cameraOff = next);
    unawaited(CallMediaControls.publishCamera(_call.id, off: next));
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
      if (mounted) setState(() => _speakerOn = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  @override
  void dispose() {
    CallCoordinator.instance.unbindHostedEndHandler(_boundEnd);
    _ticker?.cancel();
    _qualityTimer?.cancel();
    if (!_ending) {
      unawaited(_cleanup(notifyServer: true));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _tile(
        label: 'Вы',
        child: _isVideo && !_cameraOff
            ? RTCVideoView(_localRenderer, mirror: true)
            : _avatar('Вы'),
      ),
      ..._remotes.entries.map((e) {
        final name = _peerLabel(e.key);
        final muted = _remoteMuted[e.key] == true;
        final camOff = _remoteCameraOff[e.key] == true;
        final showVideo = e.value.srcObject != null && !camOff;
        return _tile(
          label: name,
          muted: muted,
          child: showVideo ? RTCVideoView(e.value) : _avatar(name),
        );
      }),
    ];

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
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Свернуть',
                      onPressed: CallCoordinator.instance.minimizeCall,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        _weakLink ? 'Плохая связь' : _status,
                        style: TextStyle(
                          color: _weakLink ? const Color(0xFFFFD38A) : Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (_durationLabel.isNotEmpty)
                      Text(
                        _durationLabel,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _initializing
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.count(
                        crossAxisCount: tiles.length <= 1 ? 1 : 2,
                        padding: const EdgeInsets.all(8),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: tiles,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        _micMuted ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                      onPressed: _toggleMic,
                    ),
                    if (_isVideo)
                      IconButton(
                        icon: Icon(
                          _cameraOff ? Icons.videocam_off : Icons.videocam,
                          color: Colors.white,
                        ),
                        onPressed: _toggleCamera,
                      ),
                    if (_isVideo)
                      IconButton(
                        icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                        onPressed: _switchCamera,
                      ),
                    IconButton(
                      icon: Icon(
                        _speakerOn ? Icons.volume_up : Icons.hearing,
                        color: Colors.white,
                      ),
                      onPressed: _toggleSpeaker,
                    ),
                    IconButton(
                      icon: const Icon(Icons.call_end, color: Colors.red, size: 32),
                      onPressed: _hangup,
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

  String _peerLabel(int userId) {
    for (final p in _call.participants) {
      if (p.userId == userId) {
        final n = p.name?.trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    return 'Участник';
  }

  Widget _tile({
    required String label,
    required Widget child,
    bool muted = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.grey.shade900, child: child),
          Positioned(
            left: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                if (muted) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.mic_off, color: Colors.white70, size: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String label) {
    return Center(
      child: CircleAvatar(
        radius: 36,
        child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?'),
      ),
    );
  }
}
