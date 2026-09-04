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
