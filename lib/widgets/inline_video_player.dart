// Inline video player с autoplay при появлении в viewport (Telegram/Instagram стиль)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/server_config.dart';
import '../utils/video_player_helper.dart';
import 'cover_network_video.dart';

/// Видеоплеер с inline autoplay: воспроизводит при появлении в viewport,
/// ставит на паузу при скролле. Muted по умолчанию.
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final double aspectRatio;
  final VoidCallback? onTap;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.aspectRatio = 16 / 9,
    this.onTap,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isVisible = false;
  bool _isMuted = true;
  bool _initialized = false;
  bool _hasError = false;
  String? _initKey;

  static const double _visibilityThresholdPlay = 0.25;
  static const double _visibilityThresholdPause = 0.08;
  static const double _visibilityThresholdPreload = 0.12;

  void _onVisibilityChanged(VisibilityInfo info) {
    final fraction = info.visibleFraction;

    if (fraction < _visibilityThresholdPause) {
      if (_isVisible) {
        _isVisible = false;
        _pause();
      }
      return;
    }

    if (fraction >= _visibilityThresholdPreload && _controller == null) {
      unawaited(_ensurePlaying());
    }

    if (fraction >= _visibilityThresholdPlay) {
      _isVisible = true;
      if (_controller != null) {
        unawaited(VideoPlayerHelper.ensurePlaying(_controller!));
      }
    }
  }

  Future<void> _ensurePlaying() async {
    if (_controller != null) {
      await VideoPlayerHelper.ensurePlaying(_controller!);
      return;
    }

    if (_initKey == widget.videoUrl) return;
    _initKey = widget.videoUrl;

    try {
      final controller = await VideoPlayerHelper.createPreparedController(
        widget.videoUrl,
        muted: _isMuted,
        autoPlay: true,
      );

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialized = true;
      });

      if (_isVisible) {
        await VideoPlayerHelper.ensurePlaying(controller);
      }
    } catch (e) {
      debugPrint('InlineVideoPlayer init error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _initialized = true;
        });
      }
    }
  }

  void _pause() {
    _controller?.pause();
  }

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    setState(() => _isMuted = !_isMuted);
    _controller?.setVolume(_isMuted ? 0 : 1);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('inline_video_${widget.videoUrl.hashCode}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (!_initialized || _controller == null) ...[
                if (widget.thumbnailUrl != null)
                  CachedNetworkImage(
                    imageUrl: ServerConfig.resolvePublisherAvatarUrl(
                      widget.thumbnailUrl!,
                    ),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: 640,
                    placeholder: (_, __) => Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                else
                  _placeholder(),
              ] else if (!_hasError && _controller != null)
                CoverNetworkVideo(controller: _controller!),

              if (_hasError)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    _placeholder(),
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                            _initialized = false;
                            _initKey = null;
                            _controller?.dispose();
                            _controller = null;
                          });
                          unawaited(_ensurePlaying());
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Повторить'),
                      ),
                    ),
                  ],
                ),

              if (_initialized && !_hasError)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _isMuted = !_isMuted);
                      _controller?.setVolume(_isMuted ? 0 : 1);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
}
