import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/server_config.dart';
import '../widgets/chat_voice_waveform.dart';

/// Пузырь голосового сообщения с waveform и прогрессом воспроизведения.
class ChatVoiceBubble extends StatefulWidget {
  const ChatVoiceBubble({
    super.key,
    required this.message,
    required this.foregroundColor,
    required this.accentColor,
    this.activeColor,
  });

  final ChatMessage message;
  final Color foregroundColor;
  final Color accentColor;
  final Color? activeColor;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  int get _fallbackSec => widget.message.voiceDurationSec ?? 0;

  String _format(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    if (m > 0) return '$m:${r.toString().padLeft(2, '0')}';
    return '0:${r.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final totalMs = _total.inMilliseconds;
    if (totalMs > 0) return _position.inMilliseconds / totalMs;
    if (_fallbackSec > 0 && _playing) {
      return (_position.inSeconds / _fallbackSec).clamp(0.0, 1.0);
    }
    return 0;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _bindStreams() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _total = d);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _togglePlay() async {
    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) return;

    if (_playing) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _playing = false);
      return;
    }

    setState(() => _loading = true);
    try {
      _bindStreams();
      final resolved = ServerConfig.resolveMediaUrl(url);
      if (_position > Duration.zero && _total > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(resolved));
      }
      if (!mounted) return;
      setState(() {
        _playing = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? widget.accentColor;
    final timeLabel = _playing || _position > Duration.zero
        ? _format(_position)
        : _format(Duration(seconds: _fallbackSec));

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _loading ? null : _togglePlay,
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.foregroundColor,
                    ),
                  )
                : Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: active,
                  ),
          ),
          Expanded(
            child: ChatVoiceWaveform(
              seed: widget.message.id,
              progress: _progress,
              color: widget.foregroundColor,
              activeColor: active,
              barCount: 24,
              height: 26,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            timeLabel,
            style: TextStyle(
              color: widget.foregroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
