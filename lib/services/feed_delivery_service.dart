import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feed_delivery.dart';

/// Сервис для управления доставкой контента в ленты
class FeedDeliveryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Создать запись доставки
  static Future<void> createDelivery({
    required String postId,
    required String contentType, // 'post' или 'reel'
    required bool goesToMainFeed,
    required bool goesToReelsFeed,
    required bool goesToCommunityWall,
    required bool goesToSubscriptions,
  }) async {
    try {
      final deliveryRef = _firestore.collection('feed_delivery').doc();
      final delivery = FeedDelivery(
        id: deliveryRef.id,
        postId: postId,
        contentType: contentType,
        goesToMainFeed: goesToMainFeed,
        goesToReelsFeed: goesToReelsFeed,
        goesToCommunityWall: goesToCommunityWall,
        goesToSubscriptions: goesToSubscriptions,
        createdAt: DateTime.now(),
      );

      await deliveryRef.set(delivery.toFirestore());
    } catch (e) {
      print('Error creating feed delivery: $e');
      rethrow;
    }
  }

  /// Обновить доставку
  static Future<void> updateDelivery({
    required String postId,
    bool? goesToMainFeed,
    bool? goesToReelsFeed,
    bool? goesToCommunityWall,
    bool? goesToSubscriptions,
  }) async {
    try {
      final deliverySnapshot = await _firestore
          .collection('feed_delivery')
          .where('postId', isEqualTo: postId)
          .limit(1)
          .get();

      if (deliverySnapshot.docs.isEmpty) {
        throw Exception('Delivery not found');
      }

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (goesToMainFeed != null) updates['goesToMainFeed'] = goesToMainFeed;
      if (goesToReelsFeed != null) updates['goesToReelsFeed'] = goesToReelsFeed;
      if (goesToCommunityWall != null) {
        updates['goesToCommunityWall'] = goesToCommunityWall;
      }
      if (goesToSubscriptions != null) {
        updates['goesToSubscriptions'] = goesToSubscriptions;
      }

      await deliverySnapshot.docs.first.reference.update(updates);
    } catch (e) {
      print('Error updating feed delivery: $e');
      rethrow;
    }
  }

  /// Получить доставку для поста
  static Future<FeedDelivery?> getDelivery(String postId) async {
    try {
      final snapshot = await _firestore
          .collection('feed_delivery')
          .where('postId', isEqualTo: postId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return FeedDelivery.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('Error getting feed delivery: $e');
      return null;
    }
  }

  /// Получить все посты для общей ленты
  static Stream<List<String>> getMainFeedPostIds() {
    return _firestore
        .collection('feed_delivery')
        .where('goesToMainFeed', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FeedDelivery.fromFirestore(doc).postId)
            .toList());
  }

  /// Получить все рилсы для ленты рилсов
  static Stream<List<String>> getReelsFeedPostIds() {
    return _firestore
        .collection('feed_delivery')
        .where('goesToReelsFeed', isEqualTo: true)
        .where('contentType', isEqualTo: 'reel')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FeedDelivery.fromFirestore(doc).postId)
            .toList());
  }

  /// Получить посты для ленты подписок
  static Stream<List<String>> getSubscriptionsFeedPostIds(String userId) {
    // Получаем подписки пользователя
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('following')
        .snapshots()
        .asyncMap((followingSnapshot) async {
      if (followingSnapshot.docs.isEmpty) return <String>[];

      final followingIds = followingSnapshot.docs.map((doc) => doc.id).toList();
      
      // Получаем посты от подписок, которые должны попадать в ленту подписок
      final deliveries = <String>[];
      for (var i = 0; i < followingIds.length; i += 10) {
        final batch = followingIds.skip(i).take(10).toList();
        final postsSnapshot = await _firestore
            .collection('posts')
            .where('authorId', whereIn: batch)
            .where('isDeleted', isEqualTo: false)
            .get();

        final postIds = postsSnapshot.docs.map((doc) => doc.id).toList();
        
        // Проверяем, должны ли эти посты попадать в ленту подписок
        for (final postId in postIds) {
          final delivery = await getDelivery(postId);
          if (delivery?.goesToSubscriptions == true) {
            deliveries.add(postId);
          }
        }
      }

      return deliveries;
    });
  }
}

