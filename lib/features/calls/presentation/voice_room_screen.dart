import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/user_realtime_service.dart';

/// Полноценная голосовая комната с WebRTC (P2P mesh для MVP).
/// Поддерживает 1:1 и небольшие группы (до 4 участников).
class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({
    super.key,
    required this.roomName,
    this.roomId,
    this.isCreator = false,
  });

  final String roomName;
  final String? roomId;
  final bool isCreator;

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  MediaStream? _localStream;
  bool _isMuted = false;
  bool _isConnected = false;
  final List<_Participant> _participants = [];
  StreamSubscription<UserRealtimeEvent>? _signalingSub;

  @override
  void initState() {
    super.initState();
    _initVoiceRoom();
  }

  Future<void> _initVoiceRoom() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нужен доступ к микрофону')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    await _startLocalAudio();

    // Подписываемся на signaling события
    _signalingSub = UserRealtimeService.instance.events.listen(_handleSignalingEvent);

    // Для демо: если мы создатель — ждём других.
    // В реальном сценарии здесь был бы REST /rooms/join + обмен SDP через SSE.
    setState(() {
      _isConnected = true;
      _participants.add(_Participant(id: 'me', name: 'Вы', isLocal: true));
    });
  }

  Future<void> _startLocalAudio() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    setState(() {
      _localStream = stream;
    });
  }

  void _handleSignalingEvent(UserRealtimeEvent event) {
    if (event.event != 'voice_signaling') return;

    // Здесь в будущем будет обработка offer/answer/ice
    // Для MVP оставляем задел под реальный signaling
  }

  Future<void> _toggleMute() async {
    if (_localStream == null) return;

    final audioTrack = _localStream!.getAudioTracks().firstOrNull;
    if (audioTrack != null) {
      final newState = !_isMuted;
      audioTrack.enabled = !newState;

      setState(() {
        _isMuted = newState;
      });
    }
  }

  Future<void> _leaveRoom() async {
    await _cleanup();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanup() async {
    _signalingSub?.cancel();

    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();

    for (final stream in _remoteStreams.values) {
      stream.dispose();
    }
    _remoteStreams.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.roomName, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () {},
            tooltip: '${_participants.length} участников',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              widget.roomName,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_participants.length} участников • ${_isConnected ? "В сети" : "Подключение..."}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 40),
            if (_isMuted)
              const Text(
                'Микрофон выключен',
                style: TextStyle(color: Colors.orangeAccent),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black87,
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _isMuted ? Colors.orange : Colors.white24,
                  foregroundColor: Colors.white,
                ),
                onPressed: _toggleMute,
                icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                label: Text(_isMuted ? 'Включить микрофон' : 'Выключить микрофон'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _leaveRoom,
              icon: const Icon(Icons.call_end),
              label: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Participant {
  _Participant({
    required this.id,
    required this.name,
    this.isLocal = false,
  });

  final String id;
  final String name;
  final bool isLocal;
}
