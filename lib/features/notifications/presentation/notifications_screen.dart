import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/notification_cache_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../services/user_service.dart' as user_service;
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../application/unread_notifications_provider.dart';
import 'notification_formatters.dart';
import 'widgets/notification_tile.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _unreadCount = 0;
  Object? _loadError;
  final ScrollController _scrollController = ScrollController();
  final Set<int> _followingActorIds = {};
  final Set<int> _followLoadingIds = {};
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _realtimeSub = UserRealtimeService.instance.events.listen((event) {
      if (!mounted) return;
      if (event.event == 'notification.new') {
        unawaited(_loadNotifications(refresh: true));
      } else if (event.event == 'unread_counts' && event.notifications != null) {
        setState(() => _unreadCount = event.notifications!);
      }
    });
    unawaited(_hydrateFromCache());
    _loadNotifications(refresh: true);
  }

  Future<void> _hydrateFromCache() async {
    final cached = await NotificationCacheService.load();
    if (!mounted || cached == null) return;
    setState(() {
      _notifications = cached.notifications;
      _offset = cached.notifications.length;
      _hasMore = cached.hasMore;
      _unreadCount = cached.unreadCount;
    });
    if (cached.unreadCount > 0) {
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadNotifications({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _notifications = [];
        _offset = 0;
        _hasMore = true;
        _loadError = null;
      }
    });

    try {
      final response = await NotificationService.getNotifications(
        limit: 30,
        offset: refresh ? 0 : _offset,
      );

      if (!mounted) return;
      setState(() {
        if (refresh) {
          _notifications = response.notifications;
        } else {
          _notifications.addAll(response.notifications);
        }
        _offset = _notifications.length;
        _hasMore = response.hasMore;
        _unreadCount = response.unreadCount;
        _loadError = null;
      });
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadNotifications();
  }

  NotificationItem _copyNotification(
    NotificationItem notification, {
    bool? isRead,
    DateTime? readAt,
  }) {
    return NotificationItem(
      id: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      entityType: notification.entityType,
      entityId: notification.entityId,
      actor: notification.actor,
      isRead: isRead ?? notification.isRead,
      readAt: readAt ?? notification.readAt,
      createdAt: notification.createdAt,
      data: notification.data,
      thumbnailUrl: notification.thumbnailUrl,
      postType: notification.postType,
    );
  }

  Future<void> _markGroupAsRead(NotificationDisplayItem group) async {
    final unread = group.items.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;

    for (final notification in unread) {
      try {
        await NotificationService.markAsRead(
          notificationId: notification.id,
          read: true,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userVisibleError(e))),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      for (final notification in unread) {
        final index =
            _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = _copyNotification(
            notification,
            isRead: true,
            readAt: now,
          );
        }
        _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
      }
    });
    ref.read(unreadNotificationsCountProvider.notifier).refresh();
  }

  Future<void> _markAllAsRead() async {
    try {
      await NotificationService.markAllAsRead();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map(
              (n) => n.isRead
                  ? n
                  : _copyNotification(n, isRead: true, readAt: DateTime.now()),
            )
            .toList();
        _unreadCount = 0;
      });
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
      AppHaptics.medium();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _toggleFollow(NotificationDisplayItem group) async {
    final actorId = group.primary.actor?.id;
    if (actorId == null || _followLoadingIds.contains(actorId)) return;

    setState(() => _followLoadingIds.add(actorId));
    try {
      if (_followingActorIds.contains(actorId)) {
        await user_service.UserService.unfollow(actorId);
        if (!mounted) return;
        setState(() => _followingActorIds.remove(actorId));
      } else {
        await user_service.UserService.follow(actorId);
        if (!mounted) return;
        setState(() => _followingActorIds.add(actorId));
        AppHaptics.light();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _followLoadingIds.remove(actorId));
      }
    }
  }

  Future<void> _openMessage(NotificationDisplayItem group) async {
    final actor = group.primary.actor;
    if (actor == null) return;
    try {
      final conv = await ChatService.openDirectChat(actor.id);
      if (!mounted) return;
      context.push(ChatThreadRoute.pathFor(conv), extra: conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _openActorProfile(NotificationDisplayItem group) {
    final actorId = group.primary.actor?.id;
    if (actorId == null) return;
    context.push(ProfileRoute.withUserId(actorId));
  }

  void _openPost(NotificationDisplayItem group) {
    final notification = group.primary;
    _navigateForNotification(notification);
  }

  void _openReply(NotificationDisplayItem group) {
    final notification = group.primary;
    final postId = notificationPostId(notification) ?? notification.entityId;
    if (postId == null) return;
    final channelId = notification.data?['channel_id'];
    if (channelId != null) {
      context.push('/channel/$channelId/post/$postId/comments');
    } else {
      context.push(PostCommentsRoute.pathFor(postId));
    }
  }

  void _handleNotificationTap(NotificationDisplayItem group) {
    if (!group.isRead) {
      _markGroupAsRead(group);
    }
    _navigateForNotification(group.primary);
  }

  void _navigateForNotification(NotificationItem notification) {
    if (notification.entityType == 'channel' &&
        notification.entityId != null) {
      final channelId = notification.entityId;
      final postId = notification.data?['post_id'];

      if (postId != null) {
        context.push('/channel/$channelId/post/$postId');
      } else {
        context.push('/channel/$channelId');
      }
    } else if (notification.entityType == 'post' &&
        notification.entityId != null) {
      final channelId = notification.data?['channel_id'];
      if (channelId != null) {
        context.push('/channel/$channelId/post/${notification.entityId}');
      } else {
        context.push('/post/${notification.entityId}');
      }
    } else if (notification.entityType == 'user' &&
        notification.entityId != null) {
      context.push(ProfileRoute.withUserId(notification.entityId!));
    } else if (notification.type == 'subscription_expiring' ||
        notification.type == 'subscription_expired' ||
        notification.type == 'subscription_refund_requested' ||
        notification.type == 'subscription_refund_approved' ||
        notification.type == 'subscription_refund_rejected' ||
        notification.data?['route'] == 'subscription') {
      context.push(SubscriptionRoute.path);
    } else if (notification.type == 'message' ||
        notification.entityType == 'conversation' ||
        notification.data?['route'] == 'chat') {
      final data = notification.data;
      final conversationId = _parseNotificationId(
            data?['conversation_id'] ?? data?['conversationId'],
          ) ??
          _parseNotificationId(notification.entityId);
      if (conversationId != null) {
        final actorId = _parseNotificationId(
          data?['actor_id'] ?? data?['actorId'] ?? notification.actor?.id,
        );
        final peer = ChatUserBrief(
          id: actorId ?? 0,
          name: notification.actor?.name ?? notification.title,
        );
        context.push(
          ChatThreadRoute.pathForId(conversationId),
          extra: peer,
        );
      }
    } else if (notification.type == 'follow' && notification.actor != null) {
      context.push(ProfileRoute.withUserId(notification.actor!.id));
    }
  }

  int? _parseNotificationId(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = buildNotificationSections(_notifications);
    final visibleCount = _notifications.where(isVisibleNotification).length;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Уведомления',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Прочитать все'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadNotifications(refresh: true),
        child: visibleCount == 0 && !_isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                  _loadError != null
                      ? AppEmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Не удалось загрузить',
                          subtitle: userVisibleError(
                            _loadError!,
                            fallback: 'Проверьте сеть и попробуйте снова',
                          ),
                          action: FilledButton(
                            onPressed: () => _loadNotifications(refresh: true),
                            child: const Text('Повторить'),
                          ),
                        )
                      : const AppEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Нет уведомлений',
                          subtitle:
                              'Здесь появятся лайки, комментарии и подписки',
                        ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
                itemCount: entries.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == entries.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  final entry = entries[index];
                  if (entry is NotificationSectionHeader) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                      child: Text(
                        entry.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: scheme.onSurface,
                        ),
                      ),
                    );
                  }

                  final group = (entry as NotificationRowItem).group;
                  final actorId = group.primary.actor?.id;

                  return NotificationTile(
                    group: group,
                    onTap: () => _handleNotificationTap(group),
                    onThumbnailTap: () => _openPost(group),
                    onActorTap: actorId == null
                        ? null
                        : () => _openActorProfile(group),
                    onFollowTap: group.type == 'follow' && actorId != null
                        ? () => _toggleFollow(group)
                        : null,
                    onMessageTap: group.type == 'follow' && actorId != null
                        ? () => _openMessage(group)
                        : null,
                    onReplyTap: group.type == 'comment'
                        ? () => _openReply(group)
                        : null,
                    isFollowing:
                        actorId != null && _followingActorIds.contains(actorId),
                    followLoading:
                        actorId != null && _followLoadingIds.contains(actorId),
                  );
                },
              ),
      ),
    );
  }
}
