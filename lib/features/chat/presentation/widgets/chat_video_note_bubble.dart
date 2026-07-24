import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../services/server_config.dart';
import '../../../../utils/video_player_helper.dart';
import '../../application/chat_voice_playback_coordinator.dart';

/// Telegram-style circular video note (кружок).
class ChatVideoNoteBubble extends StatefulWidget {
  const ChatVideoNoteBubble({
    super.key,
    required this.mediaUrl,
    this.durationSec,
    this.size = 196,
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
    await _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
        _playing = false;
      });
    }
    await _init();
  }

  Future<void> _init() async {
    final url = ServerConfig.resolveMediaUrl(widget.mediaUrl);
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _stopFromCoordinator() async {
    final c = _controller;
    if (c == null || !_playing) return;
    try {
      await c.pause();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
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
    await VideoPlayerHelper.ensurePlaying(c, shouldContinue: () => mounted);
    if (mounted) setState(() => _playing = true);
  }

  @override
  void dispose() {
    _coord.release(_playbackToken);
    _controller?.dispose();
    super.dispose();
  }

  String _durationLabel() {
    final fromMsg = widget.durationSec;
    final c = _controller;
    final secs = fromMsg ??
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.55), width: 2.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: _failed
                        ? Icon(Icons.videocam_off_outlined, color: scheme.onSurfaceVariant)
                        : !_ready
                            ? const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                ),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _controller!.value.size.width,
                                      height: _controller!.value.size.height,
                                      child: VideoPlayer(_controller!),
                                    ),
                                  ),
                                  if (!_playing)
                                    Container(
                                      color: Colors.black26,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 46,
                                      ),
                                    ),
                                ],
                              ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
