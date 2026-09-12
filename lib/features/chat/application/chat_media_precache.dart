import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';

import '../../../models/chat_models.dart';
import '../../../models/post_model.dart';
import '../../../services/server_config.dart';

/// Warm last photos so the thread/channel opens with pictures already there.
void precacheChatMessageMedia(Iterable<ChatMessage> messages, {int limit = 16}) {
  warmNetworkImages(chatMessageMediaUrls(messages, limit: limit));
}

List<String> chatMessageMediaUrls(Iterable<ChatMessage> messages, {int limit = 16}) {
  final urls = <String>[];
  for (final msg in messages.toList().reversed) {
    if (urls.length >= limit) break;
    final raw = (msg.mediaUrl ?? '').trim();
    if (raw.isEmpty) continue;
    final type = msg.type.toLowerCase();
    if (type != 'photo' &&
        type != 'image' &&
        type != 'album' &&
        type != 'sticker' &&
        type != 'video_note') {
      continue;
    }
    urls.add(raw);
  }
  return urls;
}

void precacheChannelPostMedia(Iterable<PostModel> posts, {int limit = 12}) {
  warmNetworkImages(channelPostMediaUrls(posts, limit: limit));
}

List<String> channelPostMediaUrls(Iterable<PostModel> posts, {int limit = 12}) {
  final urls = <String>[];
  void add(String? raw) {
    if (urls.length >= limit) return;
    final value = raw?.trim() ?? '';
    if (value.isEmpty || urls.contains(value)) return;
    urls.add(value);
  }

  for (final post in posts) {
    if (urls.length >= limit) break;
    add(post.videoThumbnail);
    add(post.linkImage);
    final media = post.body?['media'];
    if (media is! List) continue;
    for (final item in media) {
      if (urls.length >= limit) break;
      if (item is! Map) continue;
      final type = '${item['type'] ?? ''}';
      add(item['url'] as String?);
      if (type == 'video') {
        add(item['thumbnail_url'] as String?);
        add(item['thumbnail'] as String?);
      }
    }
  }
  return urls;
}

void warmNetworkImages(Iterable<String> rawUrls) {
  for (final raw in rawUrls) {
    final url = ServerConfig.resolvePublisherAvatarUrl(
      ServerConfig.resolveMediaUrl(raw),
    );
    if (url.isEmpty) continue;
    CachedNetworkImageProvider(url).resolve(
      const ImageConfiguration(size: Size(720, 720)),
    );
  }
}
