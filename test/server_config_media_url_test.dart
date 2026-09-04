import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/server_config.dart';

void main() {
  group('first-party media hosts', () {
    test('treats app, api and CDN as first-party', () {
      expect(ServerConfig.isFirstPartyMediaHost('cdn.haneat.com'), isTrue);
      expect(ServerConfig.isFirstPartyMediaHost('cdn.haneat.app'), isTrue);
      expect(ServerConfig.isFirstPartyMediaHost('haneat.app'), isTrue);
      expect(ServerConfig.isFirstPartyMediaHost('api.haneat.app'), isTrue);
      expect(ServerConfig.isFirstPartyMediaHost('www.haneat.app'), isTrue);
      expect(ServerConfig.isFirstPartyMediaHost('lh3.googleusercontent.com'), isFalse);
      expect(ServerConfig.isFirstPartyMediaHost('img.spoonacular.com'), isFalse);
    });
  });

  group('resolveSameOriginUploadUrl', () {
    test('rewrites CDN uploads to API file endpoint', () {
      final resolved = ServerConfig.resolveSameOriginUploadUrl(
        'https://cdn.haneat.com/uploads/user_2/2025/06/05/abc.jpg',
      );
      expect(resolved.contains('/api/v1/uploads/file/uploads/user_2/2025/06/05/abc.jpg'), isTrue);
      expect(resolved.contains('recipe-image-proxy'), isFalse);
    });

    test('rewrites api.haneat.app /uploads/ paths', () {
      final resolved = ServerConfig.resolveSameOriginUploadUrl(
        'https://api.haneat.app/uploads/user_1/clip.mp4',
      );
      expect(
        resolved,
        'https://api.haneat.app/api/v1/uploads/file/uploads/user_1/clip.mp4',
      );
    });

    test('keeps already-proxied uploads/file URLs', () {
      const url =
          'https://api.haneat.app/api/v1/uploads/file/uploads/user_1/clip.mp4';
      expect(ServerConfig.resolveSameOriginUploadUrl(url), url);
      expect(ServerConfig.resolvePlaybackMediaUrl(url), url);
      expect(ServerConfig.resolveVoiceMediaUrl(url), url);
    });
  });

  group('resolvePublisherAvatarUrl', () {
    test('does not send own CDN through recipe-image-proxy', () {
      final resolved = ServerConfig.resolvePublisherAvatarUrl(
        'https://cdn.haneat.com/uploads/user_2/2025/06/05/abc.jpg',
      );
      expect(resolved.contains('recipe-image-proxy'), isFalse);
      expect(resolved.contains('/uploads/file/uploads/user_2/2025/06/05/abc.jpg'), isTrue);
    });

    test('still proxies third-party avatars', () {
      final resolved = ServerConfig.resolvePublisherAvatarUrl(
        'https://lh3.googleusercontent.com/photo.jpg',
      );
      expect(resolved.contains('recipe-image-proxy'), isTrue);
      expect(
        resolved.contains(Uri.encodeComponent('https://lh3.googleusercontent.com/photo.jpg')),
        isTrue,
      );
    });
  });
}
