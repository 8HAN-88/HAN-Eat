import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/server_config.dart';
import '../application/chat_voice_playback_coordinator.dart';
import '../widgets/chat_voice_waveform.dart';

/// Пузырь голосового сообщения с waveform, scrub и скоростью 0.5×/1×/1.5×/2×.
class ChatVoiceBubble extends StatefulWidget {
  const ChatVoiceBubble({
    super.key,
    required this.message,
    required this.foregroundColor,
    required this.accentColor,
    this.activeColor,
    this.onCompleted,
  });

  final ChatMessage message;
  final Color foregroundColor;
  final Color accentColor;
  final Color? activeColor;
  /// Called when playback finishes naturally (for play-next).
  final ValueChanged<ChatMessage>? onCompleted;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  // Telegram order: start at 1×, then faster, then slow.
  static const _speeds = <double>[1.0, 1.5, 2.0, 0.5];

  final _player = AudioPlayer();
  final Object _playbackToken = Object();
  bool _playing = false;
  bool _loading = false;
  String? _playError;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  int _speedIndex = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;
  bool _audioContextReady = false;
  bool _sourceReady = false;

  int get _fallbackSec => widget.message.voiceDurationSec ?? 0;
  double get _speed => _speeds[_speedIndex];
  ChatVoicePlaybackCoordinator get _coord =>
      ChatVoicePlaybackCoordinator.instance;

  String _format(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    if (m > 0) return '$m:${r.toString().padLeft(2, '0')}';
    return '0:${r.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final totalMs = _total.inMilliseconds > 0
        ? _total.inMilliseconds
        : (_fallbackSec * 1000);
    if (totalMs <= 0) return 0;
    return (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  String get _speedLabel {
    final s = _speed;
    if (s == 0.5) return '0.5×';
    if (s == 1.0) return '1×';
    if (s == 1.5) return '1.5×';
    return '2×';
  }

  @override
  void initState() {
    super.initState();
    _coord.addListener(_onCoordinatorChanged);
    unawaited(_ensureAudioContext());
  }

  @override
  void dispose() {
    _coord.removeListener(_onCoordinatorChanged);
    _coord.release(_playbackToken);
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  void _onCoordinatorChanged() {
    final id = _coord.requestedPlayMessageId;
    if (id == null || id != widget.message.id || _playing || _loading) return;
    _coord.clearRequest(id);
    unawaited(_togglePlay());
  }

  Future<void> _stopFromCoordinator() async {
    if (!_playing && !_loading) return;
    try {
      await _player.pause();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _playing = false;
      _loading = false;
    });
  }

  Future<void> _ensureAudioContext() async {
    if (_audioContextReady || kIsWeb) return;
    try {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.defaultToSpeaker},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      _audioContextReady = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ChatVoiceBubble: audio context setup failed: $e');
      }
    }
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
      _coord.release(_playbackToken);
      widget.onCompleted?.call(widget.message);
    });
  }

  Future<void> _applySpeed() async {
    try {
      await _player.setPlaybackRate(_speed);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ChatVoiceBubble: setPlaybackRate failed: $e');
      }
    }
  }

  Future<void> _cycleSpeed() async {
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    if (_sourceReady || _playing) {
      await _applySpeed();
    }
  }

  Future<void> _seekTo(double fraction) async {
    final totalMs = _total.inMilliseconds > 0
        ? _total.inMilliseconds
        : (_fallbackSec * 1000);
    if (totalMs <= 0) return;
    final target = Duration(milliseconds: (totalMs * fraction).round());
    setState(() => _position = target);
    try {
      if (!_sourceReady) {
        await _prepareSource(autoPlay: false);
      }
      await _player.seek(target);
      if (_playing) {
        await _player.resume();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatVoiceBubble: seek failed: $e');
    }
  }

  Future<void> _prepareSource({required bool autoPlay}) async {
    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Нет файла');
    }
    await _ensureAudioContext();
    _bindStreams();
    final candidates = _voiceUrlCandidates(url);
    Object? lastError;
    for (final candidate in candidates) {
      try {
        if (kDebugMode) {
          debugPrint('ChatVoiceBubble: play $candidate');
        }
        if (autoPlay) {
          await _player.play(UrlSource(candidate));
        } else {
          await _player.setSource(UrlSource(candidate));
        }
        await _applySpeed();
        _sourceReady = true;
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Не удалось загрузить');
  }

  Future<void> _togglePlay() async {
    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) {
      setState(() => _playError = 'Нет файла');
      return;
    }

    if (_playing) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _playing = false);
      _coord.release(_playbackToken);
      return;
    }

    _coord.claim(
      _playbackToken,
      onStolen: () => unawaited(_stopFromCoordinator()),
    );

    setState(() {
      _loading = true;
      _playError = null;
    });
    try {
      if (_sourceReady && _position > Duration.zero) {
        await _applySpeed();
        await _player.resume();
      } else {
        await _prepareSource(autoPlay: true);
      }
      if (!mounted) return;
      setState(() {
        _playing = true;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ChatVoiceBubble: playback failed: $e');
      }
      _coord.release(_playbackToken);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playing = false;
        _playError = 'Не удалось воспроизвести';
      });
    }
  }

  List<String> _voiceUrlCandidates(String rawUrl) {
    final cleaned = rawUrl.trim();
    if (cleaned.isEmpty) return const [];
    final out = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || out.contains(v)) return;
      out.add(v);
    }

    add(ServerConfig.resolveVoiceMediaUrl(cleaned));
    add(ServerConfig.resolveMediaUrl(cleaned));
    add(cleaned);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? widget.accentColor;
    final timeLabel = _playing || _position > Duration.zero
        ? _format(_position)
        : _format(Duration(seconds: _fallbackSec));

    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
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
                  onSeek: _seekTo,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _cycleSpeed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: active.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _speedLabel,
                    style: TextStyle(
                      color: active,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 34,
                child: Text(
                  timeLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: widget.foregroundColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (_playError != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: GestureDetector(
                onTap: _loading ? null : _togglePlay,
                child: Text(
                  '$_playError · Повторить',
                  style: TextStyle(
                    color: widget.foregroundColor.withValues(alpha: 0.85),
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                    decorationColor:
                        widget.foregroundColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
