import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/post_types.dart';
import 'moderation_service.dart';

/// Сервис модерации постов
class PostModerationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Статусы для ручной модерации
  static const List<String> moderatorUserIds = [
    // TODO: Загрузить из настроек/конфигурации
    // 'moderator1@example.com',
    // 'moderator2@example.com',
  ];

  /// Автоматическая модерация поста при создании
  static Future<PostStatus> moderatePost(Post post) async {
    // Проверяем текст
    if (post.text != null && post.text!.isNotEmpty) {
      final textModeration = ModerationService.moderateText(post.text!);
      if (textModeration.flagged) {
        if (kDebugMode) {
          debugPrint('Post ${post.id} flagged by automatic moderation: ${textModeration.reason}');
        }
        return PostStatus.pending; // Отправляем на ручную проверку
      }
    }

    // Проверяем теги
    if (post.tags != null) {
      for (final tag in post.tags!) {
        final tagModeration = ModerationService.moderateText(tag);
        if (tagModeration.flagged) {
          if (kDebugMode) {
            debugPrint('Post ${post.id} flagged due to tag: $tag');
          }
          return PostStatus.pending;
        }
      }
    }

    // Если все проверки пройдены - публикуем сразу
    return PostStatus.published;
  }

  /// Проверить, является ли пользователь модератором
  static bool isModerator(String? userId) {
    if (userId == null) return false;
    return moderatorUserIds.contains(userId);
  }

  /// Получить очередь постов на модерацию
  static Stream<QuerySnapshot> getModerationQueue() {
    return _firestore
        .collection('posts')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Одобрить пост (опубликовать)
  static Future<void> approvePost(String postId, String moderatorId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'status': 'published',
        'moderatedAt': FieldValue.serverTimestamp(),
        'moderatedBy': moderatorId,
      });

      // Логируем действие
      await _logModerationAction(postId, moderatorId, 'approved');
    } catch (e) {
      if (kDebugMode) debugPrint('Error approving post: $e');
      rethrow;
    }
  }

  /// Отклонить пост
  static Future<void> rejectPost(
    String postId,
    String moderatorId, {
    String? reason,
  }) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'status': 'rejected',
        'moderatedAt': FieldValue.serverTimestamp(),
        'moderatedBy': moderatorId,
        if (reason != null) 'rejectionReason': reason,
      });

      await _logModerationAction(postId, moderatorId, 'rejected', reason: reason);
    } catch (e) {
      if (kDebugMode) debugPrint('Error rejecting post: $e');
      rethrow;
    }
  }

  /// Удалить пост (мягкое удаление)
  static Future<void> deletePost(String postId, String moderatorId, {String? reason}) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': moderatorId,
        if (reason != null) 'deletionReason': reason,
      });

      await _logModerationAction(postId, moderatorId, 'deleted', reason: reason);
    } catch (e) {
      if (kDebugMode) debugPrint('Error deleting post: $e');
      rethrow;
    }
  }

  /// Восстановить пост
  static Future<void> restorePost(String postId, String moderatorId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'status': 'published',
        'deletedAt': FieldValue.delete(),
        'restoredAt': FieldValue.serverTimestamp(),
        'restoredBy': moderatorId,
      });

      await _logModerationAction(postId, moderatorId, 'restored');
    } catch (e) {
      if (kDebugMode) debugPrint('Error restoring post: $e');
      rethrow;
    }
  }

  /// Получить жалобы на пост
  static Stream<QuerySnapshot> getPostReports(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Получить все посты с жалобами
  static Stream<QuerySnapshot> getReportedPosts() {
    // Возвращаем посты, у которых есть жалобы
    // Примечание: Firestore не поддерживает запросы по подколлекциям напрямую
    // В реальном приложении нужно будет хранить счетчик жалоб в документе поста
    return _firestore
        .collection('posts')
        .where('reportCount', isGreaterThan: 0)
        .orderBy('reportCount', descending: true)
        .snapshots();
  }

  /// Обработать жалобу (после проверки)
  static Future<void> handleReport(
    String postId,
    String reportId,
    String moderatorId, {
    required bool actionTaken,
    String? actionReason,
  }) async {
    try {
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('reports')
          .doc(reportId)
          .update({
        'handledAt': FieldValue.serverTimestamp(),
        'handledBy': moderatorId,
        'actionTaken': actionTaken,
        if (actionReason != null) 'actionReason': actionReason,
      });

      // Уменьшаем счетчик жалоб
      if (actionTaken) {
        await _firestore.collection('posts').doc(postId).update({
          'reportCount': FieldValue.increment(-1),
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error handling report: $e');
      rethrow;
    }
  }

  /// Логирование действий модерации
  static Future<void> _logModerationAction(
    String postId,
    String moderatorId,
    String action, {
    String? reason,
  }) async {
    try {
      await _firestore.collection('moderation_logs').add({
        'postId': postId,
        'moderatorId': moderatorId,
        'action': action,
        if (reason != null) 'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error logging moderation action: $e');
    }
  }

  /// Получить статистику модерации
  static Future<ModerationStats> getModerationStats() async {
    try {
      final pendingCount = await _firestore
          .collection('posts')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();

      final reportedCount = await _firestore
          .collection('posts')
          .where('reportCount', isGreaterThan: 0)
          .count()
          .get();

      return ModerationStats(
        pendingCount: pendingCount.count ?? 0,
        reportedCount: reportedCount.count ?? 0,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting moderation stats: $e');
      return ModerationStats(pendingCount: 0, reportedCount: 0);
    }
  }

  /// Увеличить счетчик жалоб при новой жалобе
  static Future<void> incrementReportCount(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'reportCount': FieldValue.increment(1),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error incrementing report count: $e');
    }
  }

  /// Автоматическая перемодерация (например, после изменения правил)
  static Future<void> remoderatePost(String postId) async {
    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return;

      final post = Post.fromFirestore(doc);
      final newStatus = await moderatePost(post);

      if (newStatus != post.status) {
        await _firestore.collection('posts').doc(postId).update({
          'status': newStatus.name,
          'remoderatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error remoderating post: $e');
    }
  }
}

/// Статистика модерации
class ModerationStats {
  final int pendingCount;
  final int reportedCount;

  ModerationStats({
    required this.pendingCount,
    required this.reportedCount,
  });

  int get total => pendingCount + reportedCount;
}

