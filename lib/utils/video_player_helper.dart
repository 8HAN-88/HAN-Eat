import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../services/server_config.dart';
import '../services/video_cache_service.dart';

/// Общая инициализация видео (iOS: файл из кэша + AVAudioSession + retry play).
class VideoPlayerHelper {
  static bool get _useFileOnIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static VideoPlayerController networkController(String url) {
    return VideoPlayerController.networkUrl(
      Uri.parse(ServerConfig.resolveMediaUrl(url)),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  /// Создать и подготовить контроллер (на iPhone — сначала скачать в кэш).
  static Future<VideoPlayerController> createPreparedController(
    String url, {
    bool loop = true,
    bool muted = true,
    bool autoPlay = false,
  }) async {
    VideoPlayerController controller;
    if (_useFileOnIos) {
      try {
        final file = await VideoCacheService.fileForUrl(url);
        controller = VideoPlayerController.file(file);
      } catch (e) {
        debugPrint('VideoCache failed, network fallback: $e');
        controller = networkController(url);
      }
    } else {
      controller = networkController(url);
    }
    await prepareForPlayback(
      controller,
      loop: loop,
      muted: muted,
      autoPlay: autoPlay,
    );
    return controller;
  }

  static Future<void> prepareForPlayback(
    VideoPlayerController controller, {
    bool loop = true,
    bool muted = true,
    bool autoPlay = false,
  }) async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
    }
    if (controller.value.hasError) {
      throw Exception(
        controller.value.errorDescription ?? 'video init failed',
      );
    }

    await controller.setLooping(loop);
    if (muted) {
      await controller.setVolume(0);
    }

    for (var i = 0; i < 40; i++) {
      if (controller.value.duration > Duration.zero) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (autoPlay) {
      await ensurePlaying(controller);
    }
  }

  static Future<void> ensurePlaying(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) return;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (controller.value.isPlaying) return;
      if (controller.value.hasError) {
        debugPrint('VideoPlayer error: ${controller.value.errorDescription}');
        return;
      }
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  static Future<bool> toggleMute(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) return true;
    final isMuted = controller.value.volume < 0.5;
    await controller.setVolume(isMuted ? 1.0 : 0.0);
    return !isMuted;
  }

  static Future<bool> toggleOrStart(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) return false;
    if (!controller.value.isPlaying) {
      await ensurePlaying(controller);
      return false;
    }
    await controller.pause();
    return true;
  }
}
