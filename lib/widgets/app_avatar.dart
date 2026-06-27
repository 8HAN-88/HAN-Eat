import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/server_config.dart';

/// Resolved [ImageProvider] for user/channel avatars (media URL fixup + CORS proxy on web).
ImageProvider? resolvedAvatarImage(String? url, {int decodeWidth = 96}) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) return null;
  final resolved = ServerConfig.resolvePublisherAvatarUrl(raw);
  return ResizeImage(
    CachedNetworkImageProvider(resolved),
    width: decodeWidth,
  );
}

/// Circle avatar with consistent URL resolution across the app.
class AppUserAvatar extends StatelessWidget {
  const AppUserAvatar({
    super.key,
    this.imageUrl,
    required this.displayName,
    this.radius = 20,
    this.fontSize,
    this.onTap,
    this.child,
  });

  final String? imageUrl;
  final String displayName;
  final double radius;
  final double? fontSize;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final decodeWidth = (radius * 4).round().clamp(48, 256);
    final background = resolvedAvatarImage(imageUrl, decodeWidth: decodeWidth);
    final name = displayName.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final scheme = Theme.of(context).colorScheme;

    final avatar = background != null
        ? CircleAvatar(radius: radius, backgroundImage: background)
        : Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  scheme.primary.withValues(alpha: 0.72),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: child ??
                Text(
                  initial,
                  style: TextStyle(
                    fontSize: fontSize ?? radius * 0.85,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
          );

    if (onTap == null) return avatar;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }
}
