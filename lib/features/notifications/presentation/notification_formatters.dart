import '../../../../services/notification_service.dart';

/// Типы, которые не показываем в ленте (планирование и служебное).
const hiddenNotificationTypes = <String>{
  'post_scheduled_published',
};

bool isVisibleNotification(NotificationItem item) {
  return !hiddenNotificationTypes.contains(item.type);
}

int? notificationPostId(NotificationItem item) {
  if (item.entityType == 'post' && item.entityId != null) {
    return item.entityId;
  }
  final raw = item.data?['post_id'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw');
}

/// Одна строка в ленте — одно уведомление или сгруппированные лайки на пост.
class NotificationDisplayItem {
  const NotificationDisplayItem(this.items);

  final List<NotificationItem> items;

  NotificationItem get primary => items.first;
  bool get isGrouped => items.length > 1;
  bool get isRead => items.every((e) => e.isRead);
  String get type => primary.type;
  String? get thumbnailUrl {
    for (final item in items) {
      final url = item.thumbnailUrl?.trim();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  String? get postType => primary.postType;
  int? get postId => notificationPostId(primary);

  List<NotificationActor> get actors {
    final seen = <int>{};
    final list = <NotificationActor>[];
    for (final item in items) {
      final actor = item.actor;
      if (actor != null && seen.add(actor.id)) {
        list.add(actor);
      }
    }
    return list;
  }
}

String notificationSectionLabel(String sectionKey) {
  switch (sectionKey) {
    case 'new':
      return 'Новое';
    case 'today':
      return 'Сегодня';
    case 'yesterday':
      return 'Вчера';
    case 'week':
      return 'Последние 7 дней';
    case 'month':
      return 'Последние 30 дней';
    default:
      return 'Ранее';
  }
}

String notificationSectionKey(
  DateTime createdAt, {
  required bool isUnread,
  DateTime? now,
}) {
  if (isUnread) return 'new';

  final days = _notificationCalendarDays(createdAt, now ?? DateTime.now());
  // A timestamp a few hours ahead is clock skew, not «последние 7 дней».
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return 'week';
  if (days < 30) return 'month';
  return 'older';
}

int _notificationCalendarDays(DateTime createdAt, DateTime now) {
  final local = createdAt.toLocal();
  final clock = now.toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final createdDay = DateTime(local.year, local.month, local.day);
  return today.difference(createdDay).inDays;
}

const _sectionOrder = ['new', 'today', 'yesterday', 'week', 'month', 'older'];

/// Короткое время: «18 ч.», «1 дн.», «15 июн.».
///
/// Day labels follow the calendar, same as the section headers. A 24-hour
/// [Duration.inDays] check left yesterday's evening as «5 ч.» under «Вчера»,
/// and a future timestamp as «сейчас».
String formatNotificationTime(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  final clock = (now ?? DateTime.now()).toLocal();
  final local = date.toLocal();
  final days = _notificationCalendarDays(local, clock);
  if (days < 0) return _notificationCalendarDate(local, clock);
  if (days == 0) {
    final diff = clock.difference(local);
    if (diff.isNegative) {
      if (diff.abs() < const Duration(minutes: 3)) return 'сейчас';
      return _notificationClock(local);
    }
    if (diff.inMinutes < 1) return 'сейчас';
    if (diff.inHours < 1) return '${diff.inMinutes} мин.';
    return '${diff.inHours} ч.';
  }
  if (days == 1) return '1 дн.';
  if (days < 7) return '$days дн.';
  if (days < 14) return '1 нед.';
  if (days < 30) return '${(days / 7).floor()} нед.';
  return _notificationCalendarDate(local, clock);
}

String _notificationClock(DateTime local) {
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _notificationCalendarDate(DateTime local, DateTime now) {
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

String actorDisplayName(NotificationActor actor) {
  final username = actor.username?.trim();
  if (username != null && username.isNotEmpty) return username;
  return actor.name;
}

String _actorLabel(NotificationActor actor) => actorDisplayName(actor);

String groupedActorsLabel(List<NotificationActor> actors) {
  if (actors.isEmpty) return 'Пользователь';
  if (actors.length == 1) return _actorLabel(actors.first);
  if (actors.length == 2) {
    return '${_actorLabel(actors[0])} и ${_actorLabel(actors[1])}';
  }
  final extra = actors.length - 2;
  return '${_actorLabel(actors[0])}, ${_actorLabel(actors[1])} и ещё $extra';
}

String notificationActionText(NotificationDisplayItem group) {
  final notification = group.primary;
  final postType = group.postType;
  final actors = group.actors;

  switch (notification.type) {
    case 'like':
      return _likedTargetLabel(postType);
    case 'comment':
      return 'оставил(а) комментарий';
    case 'follow':
      return 'подписался(ась) на вас';
    case 'repost':
      return group.isGrouped
          ? 'сделали репост вашей публикации'
          : 'сделал(а) репост вашей публикации';
    case 'mention':
      return 'упомянул(а) вас';
    case 'message':
      return 'отправил(а) сообщение';
    case 'channel_post':
      return 'опубликовал(а) в канале';
    case 'channel_recipe':
      return 'опубликовал(а) в канале';
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
    case 'call.incoming':
      return 'входящий звонок';
    default:
      final body = notification.body?.trim();
      if (body != null && body.isNotEmpty) return body;
      return notification.title;
  }
}

String notificationLeadText(NotificationDisplayItem group) {
  final actors = group.actors;
  if (actors.isEmpty) {
    return _sentenceCap(notificationActionText(group));
  }
  if (group.type == 'like' || group.type == 'repost') {
    return '${groupedActorsLabel(actors)} ${notificationActionText(group)}';
  }
  return '${_actorLabel(actors.first)} ${notificationActionText(group)}';
}

/// Standalone inbox lines start with a capital (sentence case).
String _sentenceCap(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return value;
  final first = trimmed[0];
  final upper = first.toUpperCase();
  if (first == upper) return trimmed;
  return '$upper${trimmed.substring(1)}';
}

String _likedTargetLabel(String? postType) {
  switch (postType) {
    case 'reel':
      return 'нравится ваш рилс';
    case 'photo':
      return 'нравится ваше фото';
    case 'text':
    case 'recipe': // legacy kitchen posts
      return 'нравится ваш пост';
    default:
      return 'нравится ваша публикация';
  }
}

List<NotificationDisplayItem> _groupSectionItems(
  List<NotificationItem> sectionItems,
) {
  final result = <NotificationDisplayItem>[];
  final used = <int>{};

  for (var i = 0; i < sectionItems.length; i++) {
    if (used.contains(i)) continue;
    final item = sectionItems[i];

    if (item.type == 'like' || item.type == 'repost') {
      final postId = notificationPostId(item);
      if (postId != null) {
        final cluster = <NotificationItem>[item];
        used.add(i);
        for (var j = i + 1; j < sectionItems.length; j++) {
          if (used.contains(j)) continue;
          final other = sectionItems[j];
          if (other.type == item.type && notificationPostId(other) == postId) {
            cluster.add(other);
            used.add(j);
          }
        }
        cluster.sort(
          (a, b) => (b.createdAt ?? DateTime(0))
              .compareTo(a.createdAt ?? DateTime(0)),
        );
        result.add(NotificationDisplayItem(cluster));
        continue;
      }
    }

    used.add(i);
    result.add(NotificationDisplayItem([item]));
  }

  result.sort(
    (a, b) => (b.primary.createdAt ?? DateTime(0))
        .compareTo(a.primary.createdAt ?? DateTime(0)),
  );
  return result;
}

List<NotificationListEntry> buildNotificationSections(
  List<NotificationItem> notifications,
) {
  final visible = notifications.where(isVisibleNotification).toList();
  if (visible.isEmpty) return [];

  final buckets = <String, List<NotificationItem>>{};
  for (final item in visible) {
    final created = item.createdAt ?? DateTime.now();
    final key = notificationSectionKey(created, isUnread: !item.isRead);
    buckets.putIfAbsent(key, () => []).add(item);
  }

  final entries = <NotificationListEntry>[];
  for (final key in _sectionOrder) {
    final sectionItems = buckets[key];
    if (sectionItems == null || sectionItems.isEmpty) continue;

    entries
        .add(NotificationSectionHeader(label: notificationSectionLabel(key)));
    for (final group in _groupSectionItems(sectionItems)) {
      entries.add(NotificationRowItem(group));
    }
  }
  return entries;
}

sealed class NotificationListEntry {}

class NotificationSectionHeader extends NotificationListEntry {
  NotificationSectionHeader({required this.label});

  final String label;
}

class NotificationRowItem extends NotificationListEntry {
  NotificationRowItem(this.group);

  final NotificationDisplayItem group;
}
