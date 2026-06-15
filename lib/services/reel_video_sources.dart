import '../models/video_quality_preference.dart';
import 'server_config.dart';

/// Все доступные URL видео поста (транскоды, HLS, оригинал).
class ReelVideoSources {
  const ReelVideoSources({
    this.original,
    this.mp4_480p,
    this.mp4_720p,
    this.mp4_1080p,
    this.hls,
    this.thumbnail,
  });

  final String? original;
  final String? mp4_480p;
  final String? mp4_720p;
  final String? mp4_1080p;
  final String? hls;
  final String? thumbnail;

  bool get isEmpty =>
      original == null &&
      mp4_480p == null &&
      mp4_720p == null &&
      mp4_1080p == null &&
      hls == null;

  /// Любой рабочий URL (для обратной совместимости).
  String? get anyUrl =>
      mp4_1080p ?? mp4_720p ?? mp4_480p ?? hls ?? original;

  /// Быстрый старт: 720p для авто, фиксированные профили — как выбрано.
  String? fastStartUrl(VideoQualityPreference pref) {
    switch (pref) {
      case VideoQualityPreference.dataSaver:
        return mp4_480p ?? mp4_720p ?? mp4_1080p ?? original;
      case VideoQualityPreference.hd720:
        return mp4_720p ?? mp4_1080p ?? mp4_480p ?? original;
      case VideoQualityPreference.hd1080:
        return mp4_1080p ?? original ?? mp4_720p ?? mp4_480p;
      case VideoQualityPreference.max:
        return mp4_1080p ?? original ?? mp4_720p ?? mp4_480p ?? hls;
      case VideoQualityPreference.auto:
        return mp4_720p ?? mp4_480p ?? mp4_1080p ?? original ?? hls;
    }
  }

  /// Целевое качество после прогрузки (только auto: Wi‑Fi → 1080p).
  String? upgradeUrl(VideoQualityPreference pref, {required bool onWifi}) {
    if (pref != VideoQualityPreference.auto) return null;

    final start = fastStartUrl(pref);
    final target = onWifi
        ? (mp4_1080p ?? original)
        : null;
    if (target == null || target == start) return null;
    return target;
  }

  /// URL для фонового prefetch соседних рилсов.
  String? prefetchUrl(VideoQualityPreference pref) {
    switch (pref) {
      case VideoQualityPreference.max:
      case VideoQualityPreference.hd1080:
        return mp4_480p ?? mp4_720p;
      case VideoQualityPreference.hd720:
        return mp4_480p;
      case VideoQualityPreference.dataSaver:
        return mp4_480p;
      case VideoQualityPreference.auto:
        return mp4_720p ?? mp4_480p;
    }
  }

  static ReelVideoSources fromPostBody(Map<String, dynamic>? body) {
    if (body == null) return const ReelVideoSources();

    String? original;
    String? mp4_480;
    String? mp4_720;
    String? mp4_1080;
    String? hls;
    String? thumb;

    final media = body['media'];
    if (media is List) {
      for (final item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'video') {
          original = _resolve(item['url']);
          mp4_480 = _resolve(item['mp4_480p_url']);
          mp4_720 = _resolve(item['mp4_720p_url']);
          mp4_1080 = _resolve(item['mp4_1080p_url']);
          hls = _resolve(item['hls_url']);
          thumb = _resolve(item['thumbnail_url'] ?? item['thumbnail']);
          break;
        }
      }
    }

    original ??= _resolve(body['video_url']);
    thumb ??= _resolve(body['video_thumbnail']);

    return ReelVideoSources(
      original: original,
      mp4_480p: mp4_480,
      mp4_720p: mp4_720,
      mp4_1080p: mp4_1080,
      hls: hls,
      thumbnail: thumb,
    );
  }

  static String? _resolve(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return ServerConfig.resolveMediaUrl(raw.trim());
    }
    return null;
  }
}
