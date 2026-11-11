import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/notifications/presentation/notification_formatters.dart';
import 'package:han_eat/services/notification_service.dart';

NotificationItem _item({
  required int id,
  required String type,
  int? postId,
  int? actorId,
  String? actorName,
  bool isRead = false,
  DateTime? createdAt,
}) {
  return NotificationItem(
    id: id,
    type: type,
    title: 'title',
    entityType: postId != null ? 'post' : null,
    entityId: postId,
    actor: actorId == null
        ? null
        : NotificationActor(
            id: actorId,
            name: actorName ?? 'User $actorId',
            username: 'user$actorId',
          ),
    isRead: isRead,
    createdAt: createdAt ?? DateTime.now(),
    data: postId != null ? {'post_id': postId} : null,
    postType: 'recipe',
  );
}

void main() {
  test('groups likes on the same post within a section', () {
    final now = DateTime.now();
    final entries = buildNotificationSections([
      _item(id: 1, type: 'like', postId: 10, actorId: 1, actorName: 'Anna'),
      _item(id: 2, type: 'like', postId: 10, actorId: 2, actorName: 'Bob'),
      _item(id: 3, type: 'comment', postId: 11, actorId: 3, actorName: 'Cat'),
    ]);

    final rows = entries.whereType<NotificationRowItem>().toList();
    expect(rows.length, 2);

    final likeGroup = rows.firstWhere((r) => r.group.type == 'like');
    expect(likeGroup.group.isGrouped, isTrue);
    expect(likeGroup.group.actors.length, 2);
    expect(
      notificationLeadText(likeGroup.group),
      contains('нравится ваш пост'),
    );
  });

  test('unread notifications go to the New section', () {
    final entries = buildNotificationSections([
      _item(id: 1, type: 'follow', actorId: 5, isRead: false),
      _item(
        id: 2,
        type: 'like',
        postId: 7,
        actorId: 6,
        isRead: true,
        createdAt: DateTime.now(),
      ),
    ]);

    final headers =
        entries.whereType<NotificationSectionHeader>().map((e) => e.label).toList();
    expect(headers.first, 'Новое');
    expect(headers, contains('Сегодня'));
  });

  test('standalone inbox lines use sentence case', () {
    final entries = buildNotificationSections([
      _item(id: 1, type: 'subscription_expiring', isRead: true),
    ]);
    final row = entries.whereType<NotificationRowItem>().single;
    expect(
      notificationLeadText(row.group),
      'Подписка скоро истекает',
    );
  });

  test('yesterday evening is one day, not leftover hours', () {
    final now = DateTime(2026, 11, 12, 0, 20);
    final created = DateTime(2026, 11, 11, 23, 40);
    expect(formatNotificationTime(created, now: now), '1 дн.');
    expect(
      notificationSectionKey(created, isUnread: false, now: now),
      'yesterday',
    );
  });

  test('a future timestamp is not filed under the last week', () {
    final now = DateTime(2026, 11, 11, 23, 40);
    final created = DateTime(2026, 11, 12, 2, 30);
    expect(
      notificationSectionKey(created, isUnread: false, now: now),
      'today',
    );
    expect(formatNotificationTime(created, now: now), '12 нояб.');
  });

  test('same calendar day still uses hours and minutes', () {
    final now = DateTime(2026, 11, 12, 15, 0);
    expect(
      formatNotificationTime(DateTime(2026, 11, 12, 12, 10), now: now),
      '2 ч.',
    );
    expect(
      formatNotificationTime(DateTime(2026, 11, 12, 14, 40), now: now),
      '20 мин.',
    );
  });

  test('hides scheduled publish notifications', () {
    final entries = buildNotificationSections([
      _item(id: 1, type: 'post_scheduled_published'),
      _item(id: 2, type: 'like', postId: 3, actorId: 1),
    ]);
    expect(entries.whereType<NotificationRowItem>().length, 1);
  });
}
