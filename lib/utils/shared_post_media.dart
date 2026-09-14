import '../models/post_model.dart';
import '../services/server_config.dart';
import 'post_display_title.dart';

/// Медиа и подпись для Instagram-карточки репоста.
class SharedPostMedia {
  SharedPostMedia._();

  static bool isVideo(PostModel post) {
    if (post.type == 'reel') return true;
    final url = post.videoUrl?.trim() ?? '';
    if (url.isNotEmpty) return true;
    final thumb = post.videoThumbnail?.trim() ?? '';
    return thumb.isNotEmpty;
  }

  static String? firstImageUrl(PostModel post) {
    final body = post.body;
    if (body != null) {
      final photos = body['photos'];
      if (photos is List) {
        for (final item in photos) {
          final url = item.toString().trim();
          if (url.isNotEmpty) return ServerConfig.resolveMediaUrl(url);
        }
      }
      final media = body['media'];
      if (media is List) {
        for (final item in media) {
          if (item is! Map) continue;
          final type = '${item['type'] ?? ''}';
          if (type != 'image' && type != 'photo') continue;
          final url = item['url']?.toString().trim() ?? '';
          if (url.isNotEmpty) return ServerConfig.resolveMediaUrl(url);
        }
      }
    }
    final legacy = extractLegacyBodyImageUrl(body);
    if (legacy == null || legacy.isEmpty) return null;
    return ServerConfig.resolveMediaUrl(legacy);
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
