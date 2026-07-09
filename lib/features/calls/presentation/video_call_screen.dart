import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Экран видео-звонка с локальным WebRTC превью и контролами.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.contactName,
    this.isGroupCall = false,
  });

  final String contactName;
  final bool isGroupCall;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _initializing = true;
  String _status = 'Подключение...';
  DateTime? _callStartedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    final mic = await Permission.microphone.request();
    final camera = await Permission.camera.request();
    if (!mic.isGranted || !camera.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужны доступы к камере и микрофону')),
      );
      Navigator.of(context).pop();
      return;
    }

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      });
      _localRenderer.srcObject = stream;
      _localStream = stream;
      await Helper.setSpeakerphoneOn(_speakerOn);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Идёт звонок';
        _callStartedAt = DateTime.now();
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось инициализировать звонок')),
      );
      Navigator.of(context).pop();
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
    await _cleanup();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;
    await _localRenderer.dispose();
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
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    widget.isGroupCall ? 'Групповой звонок' : widget.contactName,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _initializing
                        ? const Center(child: CircularProgressIndicator())
                        : _cameraOff
                            ? Container(
                                color: Colors.grey.shade900,
                                alignment: Alignment.center,
                                child: Text(
                                  widget.contactName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                  ),
                                ),
                              )
                            : RTCVideoView(
                                _localRenderer,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                mirror: true,
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
                  _CallButton(
                    icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                    label: 'Видео',
                    onPressed: _toggleCamera,
                  ),
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
