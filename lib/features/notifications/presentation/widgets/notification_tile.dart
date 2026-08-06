import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/haptics/app_haptics.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/server_config.dart';
import '../../../../services/user_service.dart' as user_service;
import '../../../../widgets/app_avatar.dart';
import '../notification_formatters.dart';

class NotificationTile extends StatefulWidget {
  const NotificationTile({
    super.key,
    required this.group,
    required this.onTap,
    this.onThumbnailTap,
    this.onActorTap,
    this.onFollowTap,
    this.onMessageTap,
    this.onReplyTap,
    this.isFollowing = false,
    this.followLoading = false,
  });

  final NotificationDisplayItem group;
  final VoidCallback onTap;
  final VoidCallback? onThumbnailTap;
  final VoidCallback? onActorTap;
  final VoidCallback? onFollowTap;
  final VoidCallback? onMessageTap;
  final VoidCallback? onReplyTap;
  final bool isFollowing;
  final bool followLoading;

  @override
  State<NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<NotificationTile> {
  bool? _resolvedFollowing;

  @override
  void initState() {
    super.initState();
    if (widget.group.type == 'follow') {
      _loadFollowState();
    }
  }

  @override
  void didUpdateWidget(covariant NotificationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.type == 'follow' &&
        widget.group.primary.actor?.id != oldWidget.group.primary.actor?.id) {
      _loadFollowState();
    }
    if (widget.isFollowing) {
      _resolvedFollowing = true;
    }
  }

  Future<void> _loadFollowState() async {
    final actorId = widget.group.primary.actor?.id;
    if (actorId == null) return;
    try {
      final profile = await user_service.UserService.getProfile(actorId);
      if (!mounted) return;
      setState(() => _resolvedFollowing = profile.isFollowing ?? false);
    } catch (_) {}
  }

  bool get _isFollowing =>
      widget.isFollowing || (_resolvedFollowing ?? false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notification = widget.group.primary;
    final lead = notificationLeadText(widget.group);
    final time = formatNotificationTime(notification.createdAt);
    final showFollow = notification.type == 'follow' && widget.onFollowTap != null;
    final showThumbnail = !showFollow && _shouldShowThumbnail();
    final isComment = notification.type == 'comment';

    final isUnread = !widget.group.isRead;

    return Material(
      color: isUnread
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : scheme.surface,
      elevation: isUnread ? 1 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          AppHaptics.light();
          widget.onTap();
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.group.isRead)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AvatarCluster(
                        group: widget.group,
                        onTap: widget.onActorTap,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LeadText(lead: lead, time: time),
                            if (isComment &&
                                notification.body != null &&
                                notification.body!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _CommentQuote(text: notification.body!.trim()),
                              if (widget.onReplyTap != null) ...[
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () {
                                    AppHaptics.selection();
                                    widget.onReplyTap!();
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: Text(
                                    'Ответить',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                            if (showFollow) ...[
                              const SizedBox(height: 10),
                              _FollowActions(
                                isFollowing: _isFollowing,
                                followLoading: widget.followLoading,
                                onFollowTap: widget.onFollowTap,
                                onFollowingTap: widget.onActorTap,
                                onMessageTap: widget.onMessageTap,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showThumbnail) ...[
                        const SizedBox(width: 10),
                        _PostThumbnail(
                          url: widget.group.thumbnailUrl,
                          postType: widget.group.postType,
                          onTap: widget.onThumbnailTap ?? widget.onTap,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowThumbnail() {
    if (widget.group.thumbnailUrl != null &&
        widget.group.thumbnailUrl!.trim().isNotEmpty) {
      return true;
    }
    return widget.group.postId != null;
  }
}

class _LeadText extends StatelessWidget {
  const _LeadText({required this.lead, required this.time});

  final String lead;
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: lead,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (time.isNotEmpty)
            TextSpan(
              text: ' · $time',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _CommentQuote extends StatelessWidget {
  const _CommentQuote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
          height: 1.3,
        ),
      ),
    );
  }
}

class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.group, this.onTap});

  final NotificationDisplayItem group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actors = group.actors;
    final badge = _badgeForType(group.type);

    if (actors.length >= 2 && group.isGrouped) {
      return SizedBox(
        width: 52,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 4,
              child: _smallAvatar(context, actors[0]),
            ),
            Positioned(
              left: 20,
              top: 0,
              child: _smallAvatar(context, actors[1]),
            ),
            if (badge != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: _badge(badge, scheme),
              ),
          ],
        ),
      );
    }

    final actor = actors.isNotEmpty ? actors.first : null;
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
              displayName: actor?.name ?? group.primary.title,
              onTap: onTap,
            ),
          ),
          if (badge != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: _badge(badge, scheme),
            ),
        ],
      ),
    );
  }

  Widget _smallAvatar(BuildContext context, NotificationActor actor) {
    final borderColor = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: AppUserAvatar(
        radius: 18,
        imageUrl: actor.avatarUrl,
        displayName: actor.name,
        onTap: onTap,
      ),
    );
  }

  Widget _badge(_BadgeStyle badge, ColorScheme scheme) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: badge.background,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(badge.icon, size: 11, color: badge.iconColor),
    );
  }

  _BadgeStyle? _badgeForType(String type) {
    switch (type) {
      case 'like':
        return const _BadgeStyle(
          icon: Icons.favorite,
          background: Color(0xFFFF3040),
          iconColor: Colors.white,
        );
      case 'comment':
        return const _BadgeStyle(
          icon: Icons.chat_bubble_rounded,
          background: Color(0xFF0095F6),
          iconColor: Colors.white,
        );
      case 'follow':
        return const _BadgeStyle(
          icon: Icons.person_add_alt_1_rounded,
          background: Color(0xFF0095F6),
          iconColor: Colors.white,
        );
      case 'repost':
        return const _BadgeStyle(
          icon: Icons.repeat_rounded,
          background: Color(0xFF7C4DFF),
          iconColor: Colors.white,
        );
      case 'mention':
        return const _BadgeStyle(
          icon: Icons.alternate_email_rounded,
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

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({
    required this.url,
    required this.postType,
    this.onTap,
  });

  final String? url;
  final String? postType;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = url?.trim();
    final hasImage = resolved != null && resolved.isNotEmpty;

    Widget child;
    if (hasImage) {
      child = CachedNetworkImage(
        imageUrl: ServerConfig.resolvePublisherAvatarUrl(resolved),
        fit: BoxFit.cover,
        memCacheWidth: 144,
        fadeInDuration: const Duration(milliseconds: 150),
        errorWidget: (_, __, ___) => _placeholder(scheme, postType),
      );
    } else {
      child = _placeholder(scheme, postType);
    }

    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              AppHaptics.selection();
              onTap!();
            },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, String? type) {
    IconData icon;
    switch (type) {
      case 'recipe':
        icon = Icons.article_outlined;
        break;
      case 'reel':
        icon = Icons.play_circle_outline_rounded;
        break;
      case 'photo':
        icon = Icons.image_outlined;
        break;
      default:
        icon = Icons.article_outlined;
    }
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
    );
  }
}

class _FollowActions extends StatelessWidget {
  const _FollowActions({
    required this.isFollowing,
    required this.followLoading,
    this.onFollowTap,
    this.onFollowingTap,
    this.onMessageTap,
  });

  final bool isFollowing;
  final bool followLoading;
  final VoidCallback? onFollowTap;
  /// Opens the actor profile when already following (avoids a dead chip).
  final VoidCallback? onFollowingTap;
  final VoidCallback? onMessageTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (!isFollowing)
          _ActionChipButton(
            label: 'Подписаться',
            filled: true,
            loading: followLoading,
            onTap: onFollowTap,
          )
        else
          _ActionChipButton(
            label: 'Вы подписаны',
            filled: false,
            onTap: onFollowingTap,
          ),
        if (onMessageTap != null)
          _ActionChipButton(
            label: 'Написать',
            filled: false,
            onTap: onMessageTap,
          ),
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.label,
    required this.filled,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const igBlue = Color(0xFF0095F6);

    if (filled) {
      return FilledButton(
        onPressed: loading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: igBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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
            : Text(label, style: const TextStyle(fontSize: 13)),
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
