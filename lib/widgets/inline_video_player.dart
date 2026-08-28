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
  final VoidCallback? onDoubleTap;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.aspectRatio = 16 / 9,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isVisible = false;
  bool _isMuted = true;
  bool _initialized = false;
  bool _hasError = false;
  bool _appVisible = true;
  String? _initKey;
  Timer? _disposeWhenHiddenTimer;
  bool _hadVideoFrame = false;

  static const double _visibilityThresholdPlay = 0.6;
  static const double _visibilityThresholdPause = 0.18;
  static const double _visibilityThresholdPreload = 0.45;

  bool get _canAutoPlay => _isVisible && _appVisible;

  void _onVisibilityChanged(VisibilityInfo info) {
    final fraction = info.visibleFraction;

    if (fraction < _visibilityThresholdPause) {
      if (_isVisible) {
        _isVisible = false;
        _pause();
        _scheduleDisposeWhenHidden();
      }
      return;
    }

    _disposeWhenHiddenTimer?.cancel();

    if (fraction >= _visibilityThresholdPreload && _controller == null) {
      unawaited(_ensurePlaying());
    }

    if (fraction >= _visibilityThresholdPlay) {
      _isVisible = true;
      if (_controller != null) {
        unawaited(
          VideoPlayerHelper.ensurePlaying(
            _controller!,
            shouldContinue: () => mounted && _canAutoPlay,
          ),
        );
      }
    }
  }

  Future<void> _ensurePlaying() async {
    if (_controller != null) {
      await VideoPlayerHelper.ensurePlaying(
        _controller!,
        shouldContinue: () => mounted && _canAutoPlay,
      );
      return;
    }

    if (_initKey == widget.videoUrl) return;
    _initKey = widget.videoUrl;

    try {
      final controller = await VideoPlayerHelper.createPreparedController(
        widget.videoUrl,
        muted: _isMuted,
        autoPlay: false,
      );

      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.addListener(_onVideoTick);
      setState(() {
        _controller = controller;
        _initialized = true;
      });

      if (_canAutoPlay) {
        await VideoPlayerHelper.ensurePlaying(
          controller,
          shouldContinue: () => mounted && _canAutoPlay,
        );
      } else {
        await controller.pause();
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

  void _onVideoTick() {
    if (!mounted || _hadVideoFrame) return;
    if (_hasVideoFrame) {
      setState(() => _hadVideoFrame = true);
    }
  }

  bool get _hasVideoFrame {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    return controller.value.isPlaying ||
        controller.value.position > Duration.zero;
  }

  void _pause() {
    _controller?.pause();
  }

  void _scheduleDisposeWhenHidden() {
    _disposeWhenHiddenTimer?.cancel();
    _disposeWhenHiddenTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isVisible) return;
      final controller = _controller;
      controller?.removeListener(_onVideoTick);
      _controller = null;
      _initialized = false;
      _initKey = null;
      _hadVideoFrame = false;
      unawaited(controller?.dispose());
      if (mounted) setState(() {});
    });
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appVisible = false;
      _pause();
    } else if (state == AppLifecycleState.resumed) {
      _appVisible = true;
      if (_isVisible) {
        unawaited(_ensurePlaying());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeWhenHiddenTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
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
        onDoubleTap: widget.onDoubleTap,
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (widget.thumbnailUrl != null)
                CachedNetworkImage(
                  imageUrl: ServerConfig.resolvePublisherAvatarUrl(
                    widget.thumbnailUrl!,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: 640,
                  placeholder: (_, __) => _placeholder(),
                  errorWidget: (_, __, ___) => _placeholder(),
                )
              else
                _placeholder(),
              if (!_hasError && _hasVideoFrame)
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
                            _hadVideoFrame = false;
                            _controller?.removeListener(_onVideoTick);
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
      );
}
