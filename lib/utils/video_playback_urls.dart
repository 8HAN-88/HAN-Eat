import '../services/server_config.dart';

bool isHlsVideoUrl(String url) => url.toLowerCase().contains('.m3u8');

/// Кандидаты для video_player: сначала прямой URL, потом same-origin файл.
///
/// Не переписываем HLS-плейлист — сегменты в нём относительные.
/// Не заменяем CDN единственным `/uploads/file`: большой рилс через API
/// на Safari часто падает по таймауту, а прямой CDN играет.
List<String> videoPlaybackUrlCandidates(String raw) {
  final original = ServerConfig.resolveMediaUrl(raw.trim());
  if (original.isEmpty) return const [];
  if (isHlsVideoUrl(original)) return [original];

  final proxied = ServerConfig.resolveSameOriginUploadUrl(original);
  if (proxied.isEmpty || proxied == original) return [original];
  return [original, proxied];
}

List<String> expandVideoPlaybackUrls(Iterable<String> urls) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in urls) {
    for (final url in videoPlaybackUrlCandidates(raw)) {
      if (seen.add(url)) out.add(url);
    }
  }
  return out;
}

/// Для нативного `<video>` на Safari: сначала оригинал / явный URL,
/// потом остальные MP4, HLS в конце. Транскод 480p часто ещё не лежит
/// на CDN — если начать с него, плеер сразу рисует «не удалось».
List<String> durableMp4PlaybackUrls(Iterable<String?> urls) {
  final mp4 = <String>[];
  final hls = <String>[];
  for (final raw in urls) {
    final url = raw?.trim() ?? '';
    if (url.isEmpty) continue;
    if (isHlsVideoUrl(url)) {
      hls.add(url);
    } else {
      mp4.add(url);
    }
  }
  return [
    ...expandVideoPlaybackUrls(mp4),
    ...expandVideoPlaybackUrls(hls),
  ];
}
