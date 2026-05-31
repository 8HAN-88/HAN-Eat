// Inline video player с autoplay при появлении в viewport (Telegram/Instagram стиль)
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  static const double _visibilityThresholdPlay = 0.3;
  static const double _visibilityThresholdPause = 0.1;

  void _onVisibilityChanged(VisibilityInfo info) {
    final visible = info.visibleFraction >= _visibilityThresholdPlay;
    final shouldPause = info.visibleFraction < _visibilityThresholdPause;

    if (visible && !_isVisible) {
      _isVisible = true;
      _ensurePlaying();
    } else if (shouldPause && _isVisible) {
      _isVisible = false;
      _pause();
    }
  }

  Future<void> _ensurePlaying() async {
    if (_controller != null) {
      if (!_controller!.value.isPlaying) {
        await _controller!.play();
      }
      return;
    }

    if (_initKey == widget.videoUrl) return; // Уже инициализируем
    _initKey = widget.videoUrl;

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.setVolume(_isMuted ? 0 : 1);
      controller.setLooping(true);

      setState(() {
        _controller = controller;
        _initialized = true;
      });

      if (_isVisible) {
        await controller.play();
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
    // Toggle mute
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
              // Thumbnail or loading
              if (!_initialized || _controller == null) ...[
                if (widget.thumbnailUrl != null)
                  CachedNetworkImage(
                    imageUrl: widget.thumbnailUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
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
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),

              if (_hasError) _placeholder(),

              // Прозрачный overlay для захвата тапов (видео на web перехватывает клики)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _handleTap,
                  behavior: HitTestBehavior.opaque,
                ),
              ),

              // Кнопка звука — свой GestureDetector, тап переключает mute
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
          child: Icon(Icons.play_circle_filled, color: Colors.white54, size: 64),
        ),
      );
}
