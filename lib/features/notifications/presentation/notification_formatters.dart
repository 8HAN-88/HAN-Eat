import '../../../../services/notification_service.dart';

/// Типы, которые не показываем в ленте (планирование и служебное).
const hiddenNotificationTypes = <String>{
  'post_scheduled_published',
};

bool isVisibleNotification(NotificationItem item) {
  return !hiddenNotificationTypes.contains(item.type);
}

/// Заголовки секций в стиле Instagram.
String notificationSectionLabel(DateTime createdAt) {
  final now = DateTime.now();
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final createdDay = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(createdDay).inDays;

  if (diffDays == 0) return 'Сегодня';
  if (diffDays == 1) return 'Вчера';
  if (diffDays < 7) return 'Последние 7 дней';
  if (diffDays < 30) return 'Последние 30 дней';
  return 'Ранее';
}

String notificationSectionKey(DateTime createdAt) {
  final now = DateTime.now();
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final createdDay = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(createdDay).inDays;

  if (diffDays == 0) return 'today';
  if (diffDays == 1) return 'yesterday';
  if (diffDays < 7) return 'week';
  if (diffDays < 30) return 'month';
  return 'older';
}

/// Короткое время как в Instagram: «18 ч.», «1 дн.», «15 июн.».
String formatNotificationTime(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);

  if (diff.inMinutes < 1) return 'сейчас';
  if (diff.inHours < 1) return '${diff.inMinutes} мин.';
  if (diff.inHours < 24) return '${diff.inHours} ч.';
  if (diff.inDays == 1) return '1 дн.';
  if (diff.inDays < 7) return '${diff.inDays} дн.';
  if (diff.inDays < 14) return '1 нед.';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} нед.';

  const months = [
    'янв.',
    'февр.',
    'мар.',
    'апр.',
    'мая',
    'июн.',
    'июл.',
    'авг.',
    'сент.',
    'окт.',
    'нояб.',
    'дек.',
  ];
  if (local.year == now.year) {
    return '${local.day} ${months[local.month - 1]}';
  }
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String actorDisplayName(NotificationItem notification) {
  final actor = notification.actor;
  if (actor != null) {
    final username = actor.username?.trim();
    if (username != null && username.isNotEmpty) return username;
    return actor.name;
  }
  final title = notification.title.trim();
  if (title.isEmpty) return 'Пользователь';
  final parts = title.split(' ');
  return parts.isNotEmpty ? parts.first : title;
}

String notificationActionText(NotificationItem notification) {
  final postType = notification.postType;
  switch (notification.type) {
    case 'like':
      return _likedTargetLabel(postType);
    case 'comment':
      return 'оставил(а) комментарий';
    case 'follow':
      return 'подписался(ась) на вас';
    case 'repost':
      return 'сделал(а) репост вашей публикации';
    case 'mention':
      return 'упомянул(а) вас';
    case 'message':
      return 'отправил(а) сообщение';
    case 'channel_post':
      return 'опубликовал(а) в канале';
    case 'channel_recipe':
      return 'добавил(а) рецепт в канале';
    case 'channel_video':
      return 'опубликовал(а) видео в канале';
    case 'channel_announcement':
      return 'объявление в канале';
    case 'moderation_approved':
      return 'модерация: публикация одобрена';
    case 'moderation_rejected':
      return 'модерация: публикация отклонена';
    case 'moderation_warning':
      return 'предупреждение модерации';
    case 'subscription_expiring':
      return 'подписка скоро истекает';
    case 'subscription_expired':
      return 'подписка истекла';
    case 'subscription_refund_requested':
      return 'запрос возврата отправлен';
    case 'subscription_refund_approved':
      return 'возврат одобрен';
    case 'subscription_refund_rejected':
      return 'возврат отклонён';
    default:
      final body = notification.body?.trim();
      if (body != null && body.isNotEmpty) return body;
      return notification.title;
  }
}

String _likedTargetLabel(String? postType) {
  switch (postType) {
    case 'recipe':
      return 'нравится ваш рецепт';
    case 'reel':
      return 'нравится ваш рилс';
    case 'photo':
      return 'нравится ваше фото';
    case 'text':
      return 'нравится ваш пост';
    default:
      return 'нравится ваша публикация';
  }
}

List<NotificationListEntry> buildNotificationSections(
  List<NotificationItem> notifications,
) {
  final visible = notifications.where(isVisibleNotification).toList();
  if (visible.isEmpty) return [];

  final entries = <NotificationListEntry>[];
  String? currentSection;

  for (final item in visible) {
    final created = item.createdAt ?? DateTime.now();
    final sectionKey = notificationSectionKey(created);
    if (sectionKey != currentSection) {
      currentSection = sectionKey;
      entries.add(
        NotificationSectionHeader(
          label: notificationSectionLabel(created),
        ),
      );
    }
    entries.add(NotificationRowItem(item));
  }
  return entries;
}

sealed class NotificationListEntry {}

class NotificationSectionHeader extends NotificationListEntry {
  NotificationSectionHeader({required this.label});

  final String label;
}

class NotificationRowItem extends NotificationListEntry {
  NotificationRowItem(this.notification);

  final NotificationItem notification;
}
