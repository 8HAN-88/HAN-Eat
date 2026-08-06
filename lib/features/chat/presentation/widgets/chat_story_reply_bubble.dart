import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../services/server_config.dart';

class ChatStoryReplyPayload {
  const ChatStoryReplyPayload({
    required this.storyId,
    required this.text,
    required this.authorId,
    this.mediaUrl,
    this.mediaType = 'image',
    this.authorName,
    this.thumbnailUrl,
  });

  final int storyId;
  final String text;
  final int authorId;
  final String? mediaUrl;
  final String mediaType;
  final String? authorName;
  final String? thumbnailUrl;

  bool get isVideo => mediaType == 'video';

  String? get previewImageUrl {
    final thumb = thumbnailUrl?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    final media = mediaUrl?.trim();
    if (media == null || media.isEmpty) return null;
    if (isVideo) return null;
    return media;
  }

  String get previewText {
    final t = text.trim();
    if (t.isEmpty) return '🖼 Ответ на сторис';
    return '🖼 $t';
  }

  static ChatStoryReplyPayload? tryParse(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final storyId = decoded['story_id'];
      final authorId = decoded['author_id'];
      final text = (decoded['text'] as String?)?.trim() ?? '';
      if (storyId is! int || storyId <= 0) return null;
      if (authorId is! int || authorId <= 0) return null;
      if (text.isEmpty) return null;
      return ChatStoryReplyPayload(
        storyId: storyId,
        text: text,
        authorId: authorId,
        mediaUrl: decoded['media_url'] as String?,
        mediaType: decoded['media_type'] as String? ?? 'image',
        authorName: decoded['author_name'] as String?,
        thumbnailUrl: decoded['thumbnail_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
        'story_id': storyId,
        'text': text.trim(),
        'author_id': authorId,
        if (authorName != null && authorName!.trim().isNotEmpty)
          'author_name': authorName!.trim(),
        if (mediaUrl != null && mediaUrl!.trim().isNotEmpty)
          'media_url': mediaUrl!.trim(),
        'media_type': mediaType,
        if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty)
          'thumbnail_url': thumbnailUrl!.trim(),
      });
}

class ChatStoryReplyBubble extends StatelessWidget {
  const ChatStoryReplyBubble({
    super.key,
    required this.payload,
    required this.foregroundColor,
    required this.accentColor,
    required this.backgroundColor,
  });

  final ChatStoryReplyPayload payload;
  final Color foregroundColor;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final imageUrl = payload.previewImageUrl;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: accentColor.withValues(alpha: 0.12),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                if (imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: ServerConfig.resolveMediaUrl(imageUrl),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _StoryThumbFallback(
                        accentColor: accentColor,
                        isVideo: payload.isVideo,
                      ),
                    ),
                  )
                else
                  _StoryThumbFallback(
                    accentColor: accentColor,
                    isVideo: payload.isVideo,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Сторис',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if ((payload.authorName ?? '').trim().isNotEmpty)
                        Text(
                          payload.authorName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foregroundColor.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Text(
              payload.text,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 15,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryThumbFallback extends StatelessWidget {
  const _StoryThumbFallback({
    required this.accentColor,
    required this.isVideo,
  });

  final Color accentColor;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.auto_awesome_rounded,
        color: accentColor,
        size: 22,
      ),
    );
  }
}
