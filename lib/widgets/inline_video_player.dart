// Inline video player с autoplay при появлении в viewport (Telegram/Instagram стиль)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/server_config.dart';
import '../utils/video_playback_urls.dart';
import '../utils/video_player_helper.dart';
import 'cover_network_video.dart';
import 'web_dom_video_layer.dart';
import 'web_html_reel_video.dart';

/// Видеоплеер с inline autoplay: воспроизводит при появлении в viewport,
/// ставит на паузу при скролле. Muted по умолчанию.
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final List<String> fallbackUrls;
  final String? thumbnailUrl;
  final double aspectRatio;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.fallbackUrls = const [],
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
  bool _domFailed = false;

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

  List<String> get _domUrls => durableMp4PlaybackUrls([
        widget.videoUrl,
        ...widget.fallbackUrls,
      ]);

  bool get _useDomLayer =>
      WebDomVideoLayer.isPreferred && _domUrls.isNotEmpty;

  Future<void> _ensurePlaying() async {
    if (_useDomLayer) {
      if (mounted) {
        setState(() {
          _initialized = true;
          _hasError = false;
        });
      }
      return;
    }
    if (_controller != null) {
      await VideoPlayerHelper.ensurePlaying(
        _controller!,
        shouldContinue: () => mounted && _canAutoPlay,
      );
      return;
    }

    final candidates = <String>[];
    void addUrl(String raw) {
      final url = raw.trim();
      if (url.isEmpty || candidates.contains(url)) return;
      candidates.add(url);
    }

    addUrl(widget.videoUrl);
    for (final url in widget.fallbackUrls) {
      addUrl(url);
    }
    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _initialized = true;
        });
      }
      return;
    }

    final initKey = candidates.join('|');
    if (_initKey == initKey) return;
    _initKey = initKey;

    Object? lastError;
    for (final url in candidates) {
      if (!mounted) return;
      try {
        final controller = await VideoPlayerHelper.createPreparedController(
          url,
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
          _hasError = false;
        });

        if (_canAutoPlay) {
          await VideoPlayerHelper.ensurePlaying(
            controller,
            shouldContinue: () => mounted && _canAutoPlay,
          );
        } else {
          await controller.pause();
        }
        return;
      } catch (e) {
        lastError = e;
        debugPrint('InlineVideoPlayer init error for $url: $e');
      }
    }

    debugPrint('InlineVideoPlayer init failed: $lastError');
    if (mounted) {
      setState(() {
        _hasError = true;
        _initialized = true;
      });
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
    if (!_useDomLayer) {
      _controller?.setVolume(_isMuted ? 0 : 1);
    }
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
          child: _useDomLayer
              ? _buildDomStack()
              : ClipRect(
                  child: _buildFlutterStack(),
                ),
        ),
      ),
    );
  }

  Widget _buildDomStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.thumbnailUrl != null)
          CachedNetworkImage(
            imageUrl: ServerConfig.resolvePublisherAvatarUrl(
              widget.thumbnailUrl!,
            ),
            fit: BoxFit.cover,
            memCacheWidth: 640,
            placeholder: (_, __) => _placeholder(),
            errorWidget: (_, __, ___) => _placeholder(),
          )
        else
          _placeholder(),
        if (_domFailed)
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _domFailed = false);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Повторить'),
            ),
          )
        else
          WebDomVideoLayer(
            urls: _domUrls,
            active: _isVisible || _canAutoPlay,
            playing: _canAutoPlay,
            muted: _isMuted,
            behindCanvas: true,
            onFailed: () {
              if (mounted) setState(() => _domFailed = true);
            },
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => setState(() => _isMuted = !_isMuted),
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
    );
  }

  Widget _buildFlutterStack() {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      clipBehavior: Clip.hardEdge,
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
        if (!_hasError && _hadVideoFrame && _controller != null)
          IgnorePointer(
            child: CoverNetworkVideo(controller: _controller!),
          ),
        if (_hasError)
          WebHtmlReelVideo.isSupported
              ? WebHtmlReelVideo(
                  url: ServerConfig.resolveMediaUrl(widget.videoUrl),
                  muted: _isMuted,
                  playing: _canAutoPlay,
                )
              : Stack(
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
                            _domFailed = false;
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
    );
  }

  Widget _placeholder() => const ColoredBox(
        color: Color(0xFF1A1A1A),
        child: Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            color: Colors.white38,
            size: 56,
          ),
        ),
      );
}
