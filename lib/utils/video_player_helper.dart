import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/network/connection_type.dart';
import '../models/video_quality_preference.dart';
import '../services/reel_video_sources.dart';
import '../services/server_config.dart';
import '../services/video_cache_service.dart';
import 'video_playback_urls.dart';

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

  static bool _isHlsUrl(String url) => url.toLowerCase().contains('.m3u8');

  /// MP4-транскоды кэшируем; HLS и тяжёлые оригиналы — только стриминг.
  static bool _shouldUseFileCache(String url) {
    if (!_useFileCache || _isHlsUrl(url)) return false;
    final lower = url.toLowerCase();
    if (lower.contains('_480p') ||
        lower.contains('_720p') ||
        lower.contains('_1080p')) {
      return true;
    }
    // Оригинал — не качаем целиком в фоне.
    return false;
  }

  static VideoPlayerController networkController(String url) {
    return VideoPlayerController.networkUrl(
      Uri.parse(ServerConfig.resolveMediaUrl(url)),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  static bool _isMissingVideoPlugin(Object error) {
    return error is MissingPluginException ||
        error.toString().contains('MissingPluginException');
  }

  /// Рилс: быстрый старт + fallback на другие варианты видео.
  static Future<ReelPlaybackHandle> createReelPlayback({
    required ReelVideoSources sources,
    required VideoQualityPreference qualityPref,
    bool loop = true,
    bool muted = true,
    bool autoPlay = false,
  }) async {
    final onWifi = await deviceOnWifiOrEthernet();
    final startUrls = expandVideoPlaybackUrls(sources.playbackUrls(qualityPref));
    if (startUrls.isEmpty) {
      throw Exception('no video url');
    }

    Object? lastError;
    VideoPlayerController? controller;
    var retriedMissingPlugin = false;
    for (var i = 0; i < startUrls.length; i++) {
      final url = startUrls[i];
      try {
        controller = await _createControllerForUrl(
          url,
          loop: loop,
          muted: muted,
          autoPlay: autoPlay,
          prefetchInBackground: false,
        );
        break;
      } catch (e) {
        lastError = e;
        debugPrint('Reel video init failed for $url: $e');
        if (kIsWeb &&
            !retriedMissingPlugin &&
            _isMissingVideoPlugin(e)) {
          retriedMissingPlugin = true;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          i -= 1;
        }
      }
    }

    if (controller == null) {
      throw Exception('video init failed: $lastError');
    }

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
    final candidates = expandVideoPlaybackUrls([url]);
    if (candidates.isEmpty) {
      throw Exception('no video url');
    }
    Object? lastError;
    for (final candidate in candidates) {
      try {
        return await _createControllerForUrl(
          candidate,
          loop: loop,
          muted: muted,
          autoPlay: autoPlay,
          prefetchInBackground: _shouldUseFileCache(candidate),
        );
      } catch (e) {
        lastError = e;
        debugPrint('Prepared video init failed for $candidate: $e');
      }
    }
    throw Exception('video init failed: $lastError');
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

  /// После быстрого старта — переключиться на более чёткий MP4 при хорошей сети.
  static void scheduleQualityUpgrade({
    required VideoPlayerController current,
    required String upgradeUrl,
    required bool Function(VideoPlayerController upgraded) onUpgraded,
    bool Function()? shouldAutoPlay,
    Duration delay = const Duration(milliseconds: 3500),
  }) {
    unawaited(Future<void>.delayed(delay, () async {
      if (!current.value.isInitialized || current.value.hasError) return;
      if (shouldAutoPlay != null && !shouldAutoPlay()) return;
      final position = current.value.position;
      final wasPlaying = current.value.isPlaying;
      final volume = current.value.volume;
      final looping = current.value.isLooping;
      final autoPlay = wasPlaying && (shouldAutoPlay?.call() ?? true);
      try {
        final next = await _createControllerForUrl(
          upgradeUrl,
          loop: looping,
          muted: volume < 0.5,
          autoPlay: false,
          prefetchInBackground: _shouldUseFileCache(upgradeUrl),
        );
        if (position > Duration.zero) {
          await next.seekTo(position);
        }
        final accepted = onUpgraded(next);
        if (accepted) {
          await current.dispose();
          if (autoPlay && (shouldAutoPlay?.call() ?? true)) {
            await ensurePlaying(next, shouldContinue: shouldAutoPlay);
          }
        } else {
          await next.dispose();
        }
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
    // iOS Safari / Flutter web блокирует unmuted autoplay — стартуем без звука.
    if (muted || kIsWeb) {
      await controller.setVolume(0);
    }

    if (autoPlay) {
      await ensurePlaying(controller);
    }
    if (kIsWeb && !muted && controller.value.isPlaying) {
      try {
        await controller.setVolume(1);
      } catch (_) {}
    }
  }

  static Future<void> ensurePlaying(
    VideoPlayerController controller, {
    bool Function()? shouldContinue,
  }) async {
    if (!controller.value.isInitialized) return;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (shouldContinue != null && !shouldContinue()) return;
      if (controller.value.isPlaying) return;
      if (controller.value.hasError) {
        debugPrint('VideoPlayer error: ${controller.value.errorDescription}');
        return;
      }
      try {
        await controller.play();
      } catch (e) {
        debugPrint('VideoPlayer play failed: $e');
      }
      if (kIsWeb &&
          !controller.value.isPlaying &&
          controller.value.volume > 0) {
        try {
          await controller.setVolume(0);
          await controller.play();
        } catch (e) {
          debugPrint('VideoPlayer muted retry failed: $e');
        }
      }
      if (shouldContinue != null && !shouldContinue()) {
        await controller.pause();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Web: play muted first (Safari autoplay), then restore session volume.
  static Future<void> ensurePlayingWithVolume(
    VideoPlayerController controller, {
    required bool muted,
    bool Function()? shouldContinue,
  }) async {
    await ensurePlaying(controller, shouldContinue: shouldContinue);
    if (shouldContinue != null && !shouldContinue()) return;
    if (!controller.value.isInitialized) return;
    final target = muted ? 0.0 : 1.0;
    if ((controller.value.volume < 0.5) == muted) return;
    try {
      await controller.setVolume(target);
    } catch (_) {}
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
