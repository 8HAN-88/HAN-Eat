import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../core/network/connection_type.dart';
import '../models/video_quality_preference.dart';
import '../services/reel_video_sources.dart';
import '../services/server_config.dart';
import '../services/video_cache_service.dart';

/// Результат инициализации рилса: контроллер + опциональный апгрейд качества.
class ReelPlaybackHandle {
  const ReelPlaybackHandle({
    required this.controller,
    this.upgradeUrl,
  });

  final VideoPlayerController controller;
  final String? upgradeUrl;
}

/// Общая инициализация видео (iOS: файл из кэша + AVAudioSession + retry play).
class VideoPlayerHelper {
  static bool get _useFileCache =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static bool _isHlsUrl(String url) =>
      url.toLowerCase().contains('.m3u8');

  /// MP4-транскоды кэшируем; HLS и тяжёлые оригиналы — только стриминг.
  static bool _shouldUseFileCache(String url) {
    if (!_useFileCache || _isHlsUrl(url)) return false;
    final lower = url.toLowerCase();
    if (lower.contains('_480p') || lower.contains('_720p')) return true;
    // Оригинал — не качаем целиком в фоне.
    return false;
  }

  static VideoPlayerController networkController(String url) {
    return VideoPlayerController.networkUrl(
      Uri.parse(ServerConfig.resolveMediaUrl(url)),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  /// Рилс: быстрый старт + опциональный апгрейд (auto без HLS).
  static Future<ReelPlaybackHandle> createReelPlayback({
    required ReelVideoSources sources,
    required VideoQualityPreference qualityPref,
    bool loop = true,
    bool muted = true,
    bool autoPlay = false,
  }) async {
    final onWifi = await deviceOnWifiOrEthernet();
    final startUrl = sources.fastStartUrl(qualityPref);
    if (startUrl == null || startUrl.isEmpty) {
      throw Exception('no video url');
    }

    final controller = await _createControllerForUrl(
      startUrl,
      loop: loop,
      muted: muted,
      autoPlay: autoPlay,
      prefetchInBackground: true,
    );

    final upgrade = sources.upgradeUrl(qualityPref, onWifi: onWifi);
    return ReelPlaybackHandle(
      controller: controller,
      upgradeUrl: upgrade,
    );
  }

  /// Создать и подготовить контроллер (чат, inline и т.д.).
  static Future<VideoPlayerController> createPreparedController(
    String url, {
    bool loop = true,
    bool muted = true,
    bool autoPlay = false,
  }) async {
    final controller = await _createControllerForUrl(
      url,
      loop: loop,
      muted: muted,
      autoPlay: autoPlay,
      prefetchInBackground: _shouldUseFileCache(url),
    );
    return controller;
  }

  static Future<VideoPlayerController> _createControllerForUrl(
    String url, {
    required bool loop,
    required bool muted,
    required bool autoPlay,
    required bool prefetchInBackground,
  }) async {
    VideoPlayerController controller;
    if (_shouldUseFileCache(url)) {
      final cached = await VideoCacheService.cachedFileIfExists(url);
      if (cached != null) {
        controller = VideoPlayerController.file(cached);
      } else {
        controller = networkController(url);
        if (prefetchInBackground) {
          VideoCacheService.prefetchInBackground(url);
        }
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

  /// После старта 480p — переключиться на 720p/оригинал (как Instagram).
  static void scheduleQualityUpgrade({
    required VideoPlayerController current,
    required String upgradeUrl,
    required void Function(VideoPlayerController upgraded) onUpgraded,
    Duration delay = const Duration(milliseconds: 1800),
  }) {
    unawaited(Future<void>.delayed(delay, () async {
      if (!current.value.isInitialized || current.value.hasError) return;
      final position = current.value.position;
      final wasPlaying = current.value.isPlaying;
      final volume = current.value.volume;
      final looping = current.value.isLooping;
      try {
        final next = await _createControllerForUrl(
          upgradeUrl,
          loop: looping,
          muted: volume < 0.5,
          autoPlay: wasPlaying,
          prefetchInBackground: _shouldUseFileCache(upgradeUrl),
        );
        if (position > Duration.zero) {
          await next.seekTo(position);
        }
        await current.dispose();
        onUpgraded(next);
      } catch (e) {
        debugPrint('Video quality upgrade failed: $e');
      }
    }));
  }

  /// Фоновая загрузка лёгких транскодов (480p) для соседних рилсов.
  static void prefetchUrl(String url) {
    if (url.trim().isEmpty || !_shouldUseFileCache(url)) return;
    VideoCacheService.prefetchInBackground(url);
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

    if (autoPlay) {
      await ensurePlaying(controller);
    }
  }

  static Future<void> ensurePlaying(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) return;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (controller.value.isPlaying) return;
      if (controller.value.hasError) {
        debugPrint('VideoPlayer error: ${controller.value.errorDescription}');
        return;
      }
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 100));
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
