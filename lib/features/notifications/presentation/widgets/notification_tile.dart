import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../services/notification_service.dart';
import '../../../../services/server_config.dart';
import '../../../../widgets/app_avatar.dart';
import '../notification_formatters.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    this.onActorTap,
    this.onFollowTap,
    this.isFollowing = false,
    this.followLoading = false,
  });

  final NotificationItem notification;
  final VoidCallback onTap;
  final VoidCallback? onActorTap;
  final VoidCallback? onFollowTap;
  final bool isFollowing;
  final bool followLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actor = notification.actor;
    final name = actorDisplayName(notification);
    final action = notificationActionText(notification);
    final time = formatNotificationTime(notification.createdAt);
    final showFollow = notification.type == 'follow' && onFollowTap != null;
    final showThumbnail = !showFollow && _hasThumbnail(notification);

    return Material(
      color: notification.isRead
          ? scheme.surface
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarWithBadge(
                notification: notification,
                onTap: onActorTap,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NotificationTextLine(
                      name: name,
                      action: action,
                      time: time,
                      onNameTap: onActorTap,
                    ),
                    if (notification.type == 'comment' &&
                        notification.body != null &&
                        notification.body!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (showFollow)
                _FollowButton(
                  isFollowing: isFollowing,
                  loading: followLoading,
                  onPressed: onFollowTap,
                )
              else if (showThumbnail)
                _PostThumbnail(url: notification.thumbnailUrl!),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasThumbnail(NotificationItem item) {
    final url = item.thumbnailUrl?.trim();
    return url != null && url.isNotEmpty;
  }
}

class _AvatarWithBadge extends StatelessWidget {
  const _AvatarWithBadge({
    required this.notification,
    this.onTap,
  });

  final NotificationItem notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actor = notification.actor;
    final badge = _badgeForType(notification.type);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: AppUserAvatar(
              radius: 22,
              imageUrl: actor?.avatarUrl,
              displayName: actor?.name ?? notification.title,
              onTap: onTap,
            ),
          ),
          if (badge != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: badge.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(
                  badge.icon,
                  size: 12,
                  color: badge.iconColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _BadgeStyle? _badgeForType(String type) {
    switch (type) {
      case 'like':
        return const _BadgeStyle(
          icon: Icons.favorite,
          background: Color(0xFFE91E63),
          iconColor: Colors.white,
        );
      case 'comment':
        return const _BadgeStyle(
          icon: Icons.chat_bubble,
          background: Color(0xFF0095F6),
          iconColor: Colors.white,
        );
      case 'follow':
        return const _BadgeStyle(
          icon: Icons.person_add_alt_1,
          background: Color(0xFF0095F6),
          iconColor: Colors.white,
        );
      case 'repost':
        return const _BadgeStyle(
          icon: Icons.repeat,
          background: Color(0xFF7C4DFF),
          iconColor: Colors.white,
        );
      case 'mention':
        return const _BadgeStyle(
          icon: Icons.alternate_email,
          background: Color(0xFF7C4DFF),
          iconColor: Colors.white,
        );
      case 'message':
        return const _BadgeStyle(
          icon: Icons.send_rounded,
          background: Color(0xFF0095F6),
          iconColor: Colors.white,
        );
      default:
        return null;
    }
  }
}

class _BadgeStyle {
  const _BadgeStyle({
    required this.icon,
    required this.background,
    required this.iconColor,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;
}

class _NotificationTextLine extends StatelessWidget {
  const _NotificationTextLine({
    required this.name,
    required this.action,
    required this.time,
    this.onNameTap,
  });

  final String name;
  final String action;
  final String time;
  final VoidCallback? onNameTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      color: scheme.onSurface,
      fontSize: 14,
      height: 1.3,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' $action', style: base),
          if (time.isNotEmpty)
            TextSpan(
              text: '  $time',
              style: base.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = ServerConfig.resolvePublisherAvatarUrl(url);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: CachedNetworkImage(
          imageUrl: resolved,
          fit: BoxFit.cover,
          memCacheWidth: 120,
          errorWidget: (_, __, ___) => ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              Icons.image_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.isFollowing,
    required this.loading,
    this.onPressed,
  });

  final bool isFollowing;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isFollowing) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Подписки', style: TextStyle(fontSize: 13)),
      );
    }

    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0095F6),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Подписаться', style: TextStyle(fontSize: 13)),
    );
  }
}
