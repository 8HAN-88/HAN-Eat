import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Cover-виджет не должен setState на каждый position-tick плеера.
bool shouldRebuildCoverVideo({
  required bool wasInitialized,
  required bool isInitialized,
  required double oldWidth,
  required double oldHeight,
  required double newWidth,
  required double newHeight,
  required bool hadError,
  required bool hasError,
}) {
  if (wasInitialized != isInitialized) return true;
  if (hadError != hasError) return true;
  return oldWidth != newWidth || oldHeight != newHeight;
}

/// Полноэкранное cover-видео. Rebuild только при init/ошибке/размере — не на каждый кадр.
class CoverNetworkVideo extends StatefulWidget {
  const CoverNetworkVideo({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<CoverNetworkVideo> createState() => _CoverNetworkVideoState();
}

class _CoverNetworkVideoState extends State<CoverNetworkVideo> {
  late bool _initialized;
  late bool _hasError;
  late Size _size;

  @override
  void initState() {
    super.initState();
    _syncFromController(widget.controller);
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(CoverNetworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      _syncFromController(widget.controller);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _syncFromController(VideoPlayerController controller) {
    final v = controller.value;
    _initialized = v.isInitialized;
    _hasError = v.hasError;
    _size = v.size;
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final v = widget.controller.value;
    if (!shouldRebuildCoverVideo(
      wasInitialized: _initialized,
      isInitialized: v.isInitialized,
      oldWidth: _size.width,
      oldHeight: _size.height,
      newWidth: v.size.width,
      newHeight: v.size.height,
      hadError: _hasError,
      hasError: v.hasError,
    )) {
      return;
    }
    setState(() => _syncFromController(widget.controller));
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_hasError) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined,
            color: Colors.white70, size: 48),
      );
    }

    if (_size.width <= 0 || _size.height <= 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: RepaintBoundary(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _size.width,
            height: _size.height,
            child: VideoPlayer(widget.controller),
          ),
        ),
      ),
    );
  }
}
