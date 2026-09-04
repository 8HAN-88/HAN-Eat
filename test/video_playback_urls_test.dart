import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/video_playback_urls.dart';

void main() {
  test('keeps HLS on the original URL', () {
    expect(
      videoPlaybackUrlCandidates('https://cdn.haneat.com/uploads/u/a.m3u8'),
      ['https://cdn.haneat.com/uploads/u/a.m3u8'],
    );
  });

  test('CDN mp4 stays first, same-origin file is fallback', () {
    final urls = videoPlaybackUrlCandidates(
      'https://cdn.haneat.com/uploads/user_2/2025/06/05/clip.mp4',
    );
    expect(urls.first, 'https://cdn.haneat.com/uploads/user_2/2025/06/05/clip.mp4');
    expect(urls.length, 2);
    expect(
      urls.last.contains('/api/v1/uploads/file/uploads/user_2/2025/06/05/clip.mp4'),
      isTrue,
    );
  });

  test('expandVideoPlaybackUrls de-duplicates rewritten qualities', () {
    final expanded = expandVideoPlaybackUrls([
      'https://cdn.haneat.com/uploads/u/a.mp4',
      'https://cdn.haneat.com/uploads/u/a.mp4',
    ]);
    expect(expanded.length, 2);
    expect(expanded.first.endsWith('/uploads/u/a.mp4'), isTrue);
  });

  test('durableMp4PlaybackUrls keeps original first and HLS last', () {
    final urls = durableMp4PlaybackUrls([
      'https://cdn.haneat.com/uploads/u/original.mp4',
      'https://cdn.haneat.com/uploads/u/a_480p.mp4',
      'https://cdn.haneat.com/uploads/u/a.m3u8',
      'https://cdn.haneat.com/uploads/u/a_720p.mp4',
    ]);
    expect(urls.first, 'https://cdn.haneat.com/uploads/u/original.mp4');
    expect(urls.last.contains('.m3u8'), isTrue);
    expect(urls.where((u) => u.contains('original.mp4')).length, 2);
    expect(urls.any((u) => u.contains('a_480p.mp4')), isTrue);
  });

  test('durableMp4PlaybackUrls skips empty and null entries', () {
    expect(durableMp4PlaybackUrls([null, '', '  ']), isEmpty);
  });
}
