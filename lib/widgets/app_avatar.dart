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
    this.decorated = false,
  });

  final String? imageUrl;
  final String displayName;
  final double radius;
  final double? fontSize;
  final VoidCallback? onTap;
  final Widget? child;
  final bool decorated;

  bool get _isAnimatedGif {
    final path = (imageUrl ?? '').split('?').first.toLowerCase();
    return path.endsWith('.gif');
  }

  Widget _fallbackAvatar({
    required ColorScheme scheme,
    required String initial,
  }) {
    return Container(
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
  }

  @override
  Widget build(BuildContext context) {
    final decodeWidth = (radius * 4).round().clamp(48, 256);
    final background = _isAnimatedGif
        ? null
        : resolvedAvatarImage(imageUrl, decodeWidth: decodeWidth);
    final name = displayName.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final scheme = Theme.of(context).colorScheme;
    final raw = imageUrl?.trim();
    final gifUrl = _isAnimatedGif && raw != null && raw.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(raw)
        : null;

    final avatar = gifUrl != null
        ? ClipOval(
            child: Image.network(
              gifUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _fallbackAvatar(
                scheme: scheme,
                initial: initial,
              ),
            ),
          )
        : background != null
            ? CircleAvatar(radius: radius, backgroundImage: background)
            : _fallbackAvatar(scheme: scheme, initial: initial);

    Widget out = avatar;
    if (decorated) {
      out = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)],
          ),
        ),
        child: avatar,
      );
    }
    if (onTap == null) return out;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: out,
    );
  }
}
