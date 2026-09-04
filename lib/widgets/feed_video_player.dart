import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/layout/floating_bottom_padding.dart';
import '../services/server_config.dart';
import 'inline_video_player.dart';
import 'web_dom_video_layer.dart';

/// Автор / канал для оверлея на видео в ленте.
class FeedVideoAuthorInfo {
  const FeedVideoAuthorInfo({
    required this.name,
    this.avatarUrl,
    this.subtitle,
    this.metaText,
    this.viewsText,
    this.isChannel = false,
    this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final String? subtitle;
  final String? metaText;
  final String? viewsText;
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
    this.playbackUrls = const [],
    this.onOpenFullscreen,
    this.onDoubleTap,
  });

  static const double aspectRatio = 9 / 16;

  final String videoUrl;
  final List<String> playbackUrls;
  final String? thumbnailUrl;
  final FeedVideoAuthorInfo author;
  final VoidCallback? onOpenFullscreen;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final initial =
        author.name.isNotEmpty ? author.name[0].toUpperCase() : '?';
    final avatar = author.avatarUrl != null && author.avatarUrl!.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(author.avatarUrl!)
        : null;
    final size = MediaQuery.sizeOf(context);
    final maxHeight = (size.height - floatingBottomPadding(context) - 168)
        .clamp(280.0, size.height * 0.56);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final idealHeight = width / aspectRatio;
        final height = idealHeight > maxHeight ? maxHeight : idealHeight;
        final fittedRatio = width > 0 && height > 0 ? width / height : aspectRatio;
        final media = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: InlineVideoPlayer(
                    videoUrl: videoUrl,
                    fallbackUrls: playbackUrls,
                    thumbnailUrl: thumbnailUrl,
                    aspectRatio: fittedRatio,
                    onTap: onOpenFullscreen,
                    onDoubleTap: onDoubleTap,
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
                                    if (author.metaText != null &&
                                        author.metaText!.isNotEmpty) ...[
                                      const SizedBox(width: 5),
                                      Text(
                                        '· ${author.metaText}',
                                        style: TextStyle(
                                          color:
                                              Colors.white.withValues(alpha: 0.82),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
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
                          if (author.viewsText != null &&
                              author.viewsText!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _VideoViewsBadge(count: author.viewsText!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return SizedBox(
          width: width,
          height: height,
          child: WebDomVideoLayer.isPreferred
              ? media
              : ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  child: media,
                ),
        );
      },
    );
  }
}

class _VideoViewsBadge extends StatelessWidget {
  const _VideoViewsBadge({required this.count});

  final String count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_outlined, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            count,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
