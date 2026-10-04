import '../models/post_model.dart';
import '../services/server_config.dart';
import 'post_display_title.dart';

enum SharedPostKind { video, photo, text }

/// Медиа и подпись для Instagram-карточки репоста.
class SharedPostMedia {
  SharedPostMedia._();

  static SharedPostKind kind(PostModel post) {
    if (post.type == 'reel') return SharedPostKind.video;
    final video = post.videoUrl?.trim() ?? '';
    if (video.isNotEmpty) return SharedPostKind.video;
    if (firstImageUrl(post) != null) return SharedPostKind.photo;
    return SharedPostKind.text;
  }

  static bool isVideo(PostModel post) => kind(post) == SharedPostKind.video;

  static String? _imageUrlFromItem(Object? item) {
    if (item is String) {
      final url = item.trim();
      return url.isEmpty ? null : url;
    }
    if (item is Map) {
      final type = '${item['type'] ?? ''}'.trim().toLowerCase();
      if (type == 'video' || type == 'reel') return null;
      final raw = item['url'] ?? item['src'] ?? item['image'] ?? item['photo'];
      final url = raw?.toString().trim() ?? '';
      return url.isEmpty ? null : url;
    }
    return null;
  }

  static List<String> imageUrls(PostModel post) {
    final out = <String>[];
    final seen = <String>{};
    void add(String? raw) {
      final url = raw?.trim() ?? '';
      if (url.isEmpty) return;
      final resolved = ServerConfig.resolveMediaUrl(url);
      if (resolved.isEmpty || !seen.add(resolved)) return;
      out.add(resolved);
    }

    final body = post.body;
    if (body != null) {
      final photos = body['photos'];
      if (photos is List) {
        for (final item in photos) {
          add(_imageUrlFromItem(item));
        }
      }
      final media = body['media'];
      if (media is List) {
        for (final item in media) {
          if (item is! Map) {
            add(_imageUrlFromItem(item));
            continue;
          }
          final type = '${item['type'] ?? ''}'.trim().toLowerCase();
          if (type == 'video' || type == 'reel') continue;
          if (type.isEmpty ||
              type == 'image' ||
              type == 'photo' ||
              type == 'picture') {
            add(_imageUrlFromItem(item));
          }
        }
      }
    }
    add(extractLegacyBodyImageUrl(body));
    return out;
  }

  static String? firstImageUrl(PostModel post) {
    final urls = imageUrls(post);
    return urls.isEmpty ? null : urls.first;
  }

  static String? posterUrl(PostModel post) {
    final thumb = post.videoThumbnail?.trim();
    if (thumb != null && thumb.isNotEmpty) {
      return ServerConfig.resolveMediaUrl(thumb);
    }
    return firstImageUrl(post);
  }

  static String? caption(PostModel post) {
    final title = resolvePostDisplayTitle(title: post.title, body: post.body);
    if (title != null && title.isNotEmpty) return title;
    final desc = post.description?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    return null;
  }
}
