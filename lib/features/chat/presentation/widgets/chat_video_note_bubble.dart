import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../utils/video_player_helper.dart';
import '../../../../widgets/cover_network_video.dart';
import '../../application/chat_voice_playback_coordinator.dart';

/// Telegram-style circular video note (кружок).
class ChatVideoNoteBubble extends StatefulWidget {
  const ChatVideoNoteBubble({
    super.key,
    required this.mediaUrl,
    this.durationSec,
    this.size = 208,
    this.accentColor,
  });

  final String mediaUrl;
  final int? durationSec;
  final double size;
  final Color? accentColor;

  @override
  State<ChatVideoNoteBubble> createState() => _ChatVideoNoteBubbleState();
}

class _ChatVideoNoteBubbleState extends State<ChatVideoNoteBubble> {
  VideoPlayerController? _controller;
  final Object _playbackToken = Object();
  bool _ready = false;
  bool _failed = false;
  bool _playing = false;
  bool _muted = true;
  double _progress = 0;

  ChatVoicePlaybackCoordinator get _coord =>
      ChatVoicePlaybackCoordinator.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant ChatVideoNoteBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      unawaited(_reinit());
    }
  }

  Future<void> _reinit() async {
    _controller?.removeListener(_onTick);
    await _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
        _playing = false;
        _muted = true;
        _progress = 0;
      });
    }
    await _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerHelper.networkController(widget.mediaUrl);
    _controller = controller;
    try {
      await VideoPlayerHelper.prepareForPlayback(
        controller,
        loop: true,
        muted: true,
        autoPlay: true,
      );
      controller.addListener(_onTick);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _playing = controller.value.isPlaying;
        _muted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _onTick() {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;
    final total = c.value.duration.inMilliseconds;
    final pos = c.value.position.inMilliseconds;
    final nextProgress =
        total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
    final playing = c.value.isPlaying;
    if ((nextProgress - _progress).abs() < 0.008 && playing == _playing) {
      return;
    }
    setState(() {
      _progress = nextProgress;
      _playing = playing;
    });
  }

  Future<void> _stopFromCoordinator() async {
    final c = _controller;
    if (c == null || !_playing) return;
    try {
      await c.pause();
      await c.setVolume(0);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _playing = false;
        _muted = true;
      });
    }
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      await c.pause();
      _coord.release(_playbackToken);
      if (mounted) setState(() => _playing = false);
      return;
    }
    _coord.claim(
      _playbackToken,
      onStolen: () => unawaited(_stopFromCoordinator()),
    );
    try {
      await c.setVolume(1);
      _muted = false;
    } catch (_) {}
    await VideoPlayerHelper.ensurePlaying(c, shouldContinue: () => mounted);
    if (mounted) setState(() => _playing = true);
  }

  @override
  void dispose() {
    _coord.release(_playbackToken);
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  String _durationLabel() {
    final fromMsg = widget.durationSec;
    final c = _controller;
    final remaining = c != null && c.value.isInitialized && _playing
        ? math.max(0, c.value.duration.inSeconds - c.value.position.inSeconds)
        : null;
    final secs = remaining ??
        fromMsg ??
        (c != null && c.value.isInitialized
            ? c.value.duration.inSeconds
            : null);
    if (secs == null || secs <= 0) return '';
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    final label = _durationLabel();
    final inner = widget.size - 10;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: ChatVideoNoteRingPainter(
              progress: _playing ? _progress : 0,
              trackColor: Colors.white.withValues(alpha: 0.22),
              progressColor: accent,
            ),
          ),
          SizedBox(
            width: inner,
            height: inner,
            child: Material(
              color: Colors.black,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: _failed
                  ? Icon(
                      Icons.videocam_off_outlined,
                      color: scheme.onSurfaceVariant,
                    )
                  : !_ready || _controller == null
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white70,
                            ),
                          ),
                        )
                      : CoverNetworkVideo(controller: _controller!),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: const SizedBox.expand(),
            ),
          ),
          if (_ready && !_playing)
            IgnorePointer(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          if (label.isNotEmpty)
            Positioned(
              left: 18,
              bottom: 16,
              child: IgnorePointer(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 14,
            child: IgnorePointer(
              child: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatVideoNoteRingPainter extends CustomPainter {
  ChatVideoNoteRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final sweep = (progress.clamp(0.0, 1.0) * 2 * math.pi).toDouble();
    final active = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant ChatVideoNoteRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
