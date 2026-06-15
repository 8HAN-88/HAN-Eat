import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Полноэкранное cover-видео. На iOS — rebuild по кадрам; на web/Android — меньше нагрузки на UI.
class CoverNetworkVideo extends StatefulWidget {
  const CoverNetworkVideo({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<CoverNetworkVideo> createState() => _CoverNetworkVideoState();
}

class _CoverNetworkVideoState extends State<CoverNetworkVideo> {
  bool get _needsPerFrameRebuild =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_needsPerFrameRebuild) {
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void didUpdateWidget(CoverNetworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_needsPerFrameRebuild && oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    if (!_needsPerFrameRebuild) {
      widget.controller.removeListener(_onControllerUpdate);
    }
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (widget.controller.value.isInitialized) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (controller.value.hasError) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined,
            color: Colors.white70, size: 48),
      );
    }

    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final video = RepaintBoundary(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );

    return ColoredBox(
      color: Colors.black,
      child: _needsPerFrameRebuild
          ? ListenableBuilder(listenable: controller, builder: (_, __) => video)
          : video,
    );
  }
}
