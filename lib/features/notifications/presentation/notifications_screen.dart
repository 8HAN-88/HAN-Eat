// Экран уведомлений
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/notification_service.dart';
import 'package:go_router/go_router.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _unreadCount = 0;
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadUnreadCount();
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
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
      }
    });
    
    try {
      final response = await NotificationService.getNotifications(
        limit: 20,
        offset: _offset,
      );
      
      setState(() {
        if (refresh) {
          _notifications = response.notifications;
        } else {
          _notifications.addAll(response.notifications);
        }
        _offset += response.notifications.length;
        _hasMore = response.hasMore;
        _unreadCount = response.unreadCount;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки уведомлений: $e')),
        );
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
  
  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) {
        setState(() => _unreadCount = count);
      }
    } catch (e) {
      // Игнорируем ошибки при загрузке счетчика
    }
  }
  
  Future<void> _markAsRead(NotificationItem notification) async {
    if (notification.isRead) return;
    
    try {
      await NotificationService.markAsRead(
        notificationId: notification.id,
        read: true,
      );
      
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = NotificationItem(
            id: notification.id,
            type: notification.type,
            title: notification.title,
            body: notification.body,
            entityType: notification.entityType,
            entityId: notification.entityId,
            actor: notification.actor,
            isRead: true,
            readAt: DateTime.now(),
            createdAt: notification.createdAt,
            data: notification.data,
          );
          _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  Future<void> _markAllAsRead() async {
    try {
      await NotificationService.markAllAsRead();
      setState(() {
        for (var i = 0; i < _notifications.length; i++) {
          if (!_notifications[i].isRead) {
            _notifications[i] = NotificationItem(
              id: _notifications[i].id,
              type: _notifications[i].type,
              title: _notifications[i].title,
              body: _notifications[i].body,
              entityType: _notifications[i].entityType,
              entityId: _notifications[i].entityId,
              actor: _notifications[i].actor,
              isRead: true,
              readAt: DateTime.now(),
              createdAt: _notifications[i].createdAt,
              data: _notifications[i].data,
            );
          }
        }
        _unreadCount = 0;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Все уведомления помечены как прочитанные')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  void _handleNotificationTap(NotificationItem notification) {
    // Помечаем как прочитанное
    if (!notification.isRead) {
      _markAsRead(notification);
    }
    
    // Переходим к соответствующей сущности
    if (notification.entityType == 'channel' && notification.entityId != null) {
      // Открываем канал
      final channelId = notification.entityId;
      final postId = notification.data?['post_id'];
      
      if (postId != null) {
        // Открываем конкретный пост в канале
        context.push('/channel/$channelId/post/$postId');
      } else {
        // Открываем канал
        context.push('/channel/$channelId');
      }
    } else if (notification.entityType == 'post' && notification.entityId != null) {
      // Открываем пост
      final channelId = notification.data?['channel_id'];
      if (channelId != null) {
        context.push('/channel/$channelId/post/${notification.entityId}');
      } else {
        // TODO: открыть обычный пост
      }
    } else if (notification.entityType == 'user' && notification.entityId != null) {
      // TODO: открыть профиль
      // context.push('/profile?userId=${notification.entityId}');
    }
  }
  
  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'follow':
        return Icons.person_add;
      case 'channel_post':
        return Icons.article;
      case 'channel_recipe':
        return Icons.restaurant_menu;
      case 'channel_video':
        return Icons.videocam;
      case 'channel_announcement':
        return Icons.campaign;
      case 'repost':
        return Icons.repeat;
      case 'mention':
        return Icons.alternate_email;
      case 'moderation_approved':
        return Icons.check_circle;
      case 'moderation_rejected':
        return Icons.cancel;
      case 'channel_post':
        return Icons.article;
      case 'channel_recipe':
        return Icons.restaurant_menu;
      case 'channel_video':
        return Icons.videocam;
      case 'channel_announcement':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }
  
  Color _getNotificationColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return Colors.blue;
      case 'follow':
        return Colors.green;
      case 'repost':
        return Colors.orange;
      case 'mention':
        return Colors.purple;
      case 'moderation_approved':
        return Colors.green;
      case 'moderation_rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, size: 20),
              label: const Text('Прочитать все'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadNotifications(refresh: true),
        child: _notifications.isEmpty && !_isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Нет уведомлений',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: _notifications.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _notifications.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  
                  final notification = _notifications[index];
                  
                  return InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    child: Container(
                      color: notification.isRead
                          ? null
                          : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Иконка типа уведомления
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getNotificationColor(notification.type)
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getNotificationIcon(notification.type),
                              color: _getNotificationColor(notification.type),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Контент
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Аватар актора (если есть)
                                if (notification.actor != null) ...[
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundImage: notification.actor!.avatarUrl != null
                                            ? NetworkImage(notification.actor!.avatarUrl!)
                                            : null,
                                        child: notification.actor!.avatarUrl == null
                                            ? Text(
                                                notification.actor!.name[0].toUpperCase(),
                                                style: const TextStyle(fontSize: 14),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notification.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ] else
                                  Text(
                                    notification.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                if (notification.body != null && notification.body!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    notification.body!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(notification.createdAt),
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Индикатор непрочитанного
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

