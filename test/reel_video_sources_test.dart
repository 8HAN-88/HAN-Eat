import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/video_quality_preference.dart';
import 'package:han_eat/services/reel_video_sources.dart';

void main() {
  group('ReelVideoSources', () {
    const sources = ReelVideoSources(
      original: 'https://cdn/original.mp4',
      mp4_480p: 'https://cdn/480.mp4',
      mp4_720p: 'https://cdn/720.mp4',
      mp4_1080p: 'https://cdn/1080.mp4',
      hls: 'https://cdn/hls/playlist.m3u8',
    );

    test('auto fast start prefers 720p', () {
      expect(
        sources.fastStartUrl(VideoQualityPreference.auto),
        'https://cdn/720.mp4',
      );
    });

    test('max prefers 1080p transcode', () {
      expect(
        sources.fastStartUrl(VideoQualityPreference.max),
        'https://cdn/1080.mp4',
      );
    });

    test('hd1080 uses 1080p', () {
      expect(
        sources.fastStartUrl(VideoQualityPreference.hd1080),
        'https://cdn/1080.mp4',
      );
    });

    test('max without 1080p falls back to original', () {
      const no1080 = ReelVideoSources(
        original: 'https://cdn/original.mp4',
        mp4_720p: 'https://cdn/720.mp4',
      );
      expect(
        no1080.fastStartUrl(VideoQualityPreference.max),
        'https://cdn/original.mp4',
      );
    });

    test('dataSaver caps at 480p', () {
      expect(
        sources.fastStartUrl(VideoQualityPreference.dataSaver),
        'https://cdn/480.mp4',
      );
    });

    test('hd720 uses 720p', () {
      expect(
        sources.fastStartUrl(VideoQualityPreference.hd720),
        'https://cdn/720.mp4',
      );
    });

    test('auto upgrade to 1080p on wifi', () {
      const noHls = ReelVideoSources(
        original: 'https://cdn/original.mp4',
        mp4_480p: 'https://cdn/480.mp4',
        mp4_720p: 'https://cdn/720.mp4',
        mp4_1080p: 'https://cdn/1080.mp4',
      );
      expect(
        noHls.upgradeUrl(VideoQualityPreference.auto, onWifi: true),
        'https://cdn/1080.mp4',
      );
    });

    test('auto stays at 720p on cellular', () {
      const noHls = ReelVideoSources(
        original: 'https://cdn/original.mp4',
        mp4_480p: 'https://cdn/480.mp4',
        mp4_720p: 'https://cdn/720.mp4',
        mp4_1080p: 'https://cdn/1080.mp4',
      );
      expect(
        noHls.upgradeUrl(VideoQualityPreference.auto, onWifi: false),
        isNull,
      );
    });

    test('auto upgrade to original on wifi without 1080p transcode', () {
      const no1080 = ReelVideoSources(
        original: 'https://cdn/original.mp4',
        mp4_480p: 'https://cdn/480.mp4',
        mp4_720p: 'https://cdn/720.mp4',
      );
      expect(
        no1080.upgradeUrl(VideoQualityPreference.auto, onWifi: true),
        'https://cdn/original.mp4',
      );
    });

    test('fromPostBody reads all fields', () {
      final parsed = ReelVideoSources.fromPostBody({
        'media': [
          {
            'type': 'video',
            'url': 'https://cdn/original.mp4',
            'mp4_480p_url': 'https://cdn/480.mp4',
            'mp4_720p_url': 'https://cdn/720.mp4',
            'mp4_1080p_url': 'https://cdn/1080.mp4',
            'hls_url': 'https://cdn/hls.m3u8',
            'thumbnail_url': 'https://cdn/thumb.jpg',
          },
        ],
      });
      expect(parsed.original, 'https://cdn/original.mp4');
      expect(parsed.mp4_480p, 'https://cdn/480.mp4');
      expect(parsed.mp4_720p, 'https://cdn/720.mp4');
      expect(parsed.mp4_1080p, 'https://cdn/1080.mp4');
      expect(parsed.hls, 'https://cdn/hls.m3u8');
      expect(parsed.thumbnail, 'https://cdn/thumb.jpg');
    });
  });
}
