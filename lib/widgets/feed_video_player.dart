import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/server_config.dart';
import 'inline_video_player.dart';

/// Автор / канал для оверлея на видео в ленте.
class FeedVideoAuthorInfo {
  const FeedVideoAuthorInfo({
    required this.name,
    this.avatarUrl,
    this.subtitle,
    this.isChannel = false,
    this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final String? subtitle;
  final bool isChannel;
  final VoidCallback? onTap;
}

/// Вертикальное видео в ленте (9:16) с аватаром автора/канала сверху.
class FeedVideoPlayer extends StatelessWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.author,
    this.thumbnailUrl,
    this.onOpenFullscreen,
  });

  static const double aspectRatio = 9 / 16;

  final String videoUrl;
  final String? thumbnailUrl;
  final FeedVideoAuthorInfo author;
  final VoidCallback? onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    final initial =
        author.name.isNotEmpty ? author.name[0].toUpperCase() : '?';
    final avatar = author.avatarUrl != null && author.avatarUrl!.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(author.avatarUrl!)
        : null;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: InlineVideoPlayer(
                videoUrl: videoUrl,
                thumbnailUrl: thumbnailUrl,
                aspectRatio: aspectRatio,
                onTap: onOpenFullscreen,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: author.onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: avatar != null
                                ? ResizeImage(
                                    CachedNetworkImageProvider(avatar),
                                    width: 72,
                                  )
                                : null,
                            child: avatar == null
                                ? Text(
                                    initial,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        author.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (author.isChannel) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Канал',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (author.subtitle != null &&
                                    author.subtitle!.isNotEmpty)
                                  Text(
                                    author.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
