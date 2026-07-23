import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../services/server_config.dart';
import 'inline_video_player.dart';

class ChatStickerTile extends StatelessWidget {
  const ChatStickerTile({
    super.key,
    required this.mediaUrl,
    this.animated = false,
    this.onTap,
  });

  final String mediaUrl;
  final bool animated;
  final VoidCallback? onTap;

  static bool looksAnimated(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.gif') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.json') ||
        lower.endsWith('.lottie') ||
        lower.endsWith('.tgs');
  }

  bool get _isVideo {
    final lower = mediaUrl.toLowerCase();
    return lower.endsWith('.webm') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov');
  }

  bool get _isLottie {
    final lower = mediaUrl.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.lottie');
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ServerConfig.resolveMediaUrl(mediaUrl);
    final shouldAnimate = animated || looksAnimated(mediaUrl);
    Widget child;
    if (shouldAnimate && _isVideo) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InlineVideoPlayer(
          videoUrl: resolvedUrl,
          aspectRatio: 1,
          onTap: onTap,
        ),
      );
    } else if (shouldAnimate && _isLottie) {
      child = GestureDetector(
        onTap: onTap,
        child: Lottie.network(
          resolvedUrl,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => _fallbackIcon(context),
        ),
      );
    } else {
      child = GestureDetector(
        onTap: onTap,
        child: CachedNetworkImage(
          imageUrl: resolvedUrl,
          fit: BoxFit.contain,
          // Keep GIF frames; resize cache freezes animation.
          memCacheWidth: looksAnimated(mediaUrl) &&
                  mediaUrl.toLowerCase().contains('.gif')
              ? null
              : 512,
          memCacheHeight: looksAnimated(mediaUrl) &&
                  mediaUrl.toLowerCase().contains('.gif')
              ? null
              : 512,
          placeholder: (_, __) => const SizedBox(
            height: 120,
            width: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => _fallbackIcon(context),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 112,
        minHeight: 112,
        maxWidth: 192,
        maxHeight: 192,
      ),
      child: child,
    );
  }

  Widget _fallbackIcon(BuildContext context) => SizedBox(
        height: 120,
        width: 120,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
