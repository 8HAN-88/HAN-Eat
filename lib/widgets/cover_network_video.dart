import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Полноэкранное cover-видео с принудительным rebuild каждого кадра (iOS + Chewie freeze fix).
class CoverNetworkVideo extends StatelessWidget {
  const CoverNetworkVideo({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final value = controller.value;
          if (value.hasError) {
            return const Center(
              child: Icon(Icons.videocam_off_outlined,
                  color: Colors.white70, size: 48),
            );
          }
          final size = value.size;
          if (size.width <= 0 || size.height <= 0) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          );
        },
      ),
    );
  }
}
