import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель доставки контента в ленты
/// Определяет, куда попадает пост/рилс
class FeedDelivery {
  final String id;
  final String postId; // ID поста или рилса
  final String contentType; // 'post' или 'reel'
  final bool goesToMainFeed; // Общая лента (как VK "Новости")
  final bool goesToReelsFeed; // Лента рилсов
  final bool goesToCommunityWall; // Стена сообщества
  final bool goesToSubscriptions; // Лента подписок
  final DateTime createdAt;
  final DateTime? updatedAt;

  FeedDelivery({
    required this.id,
    required this.postId,
    required this.contentType,
    this.goesToMainFeed = false,
    this.goesToReelsFeed = false,
    this.goesToCommunityWall = false,
    this.goesToSubscriptions = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory FeedDelivery.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedDelivery(
      id: doc.id,
      postId: data['postId'] as String? ?? '',
      contentType: data['contentType'] as String? ?? 'post',
      goesToMainFeed: data['goesToMainFeed'] as bool? ?? false,
      goesToReelsFeed: data['goesToReelsFeed'] as bool? ?? false,
      goesToCommunityWall: data['goesToCommunityWall'] as bool? ?? false,
      goesToSubscriptions: data['goesToSubscriptions'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'postId': postId,
      'contentType': contentType,
      'goesToMainFeed': goesToMainFeed,
      'goesToReelsFeed': goesToReelsFeed,
      'goesToCommunityWall': goesToCommunityWall,
      'goesToSubscriptions': goesToSubscriptions,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  FeedDelivery copyWith({
    String? id,
    String? postId,
    String? contentType,
    bool? goesToMainFeed,
    bool? goesToReelsFeed,
    bool? goesToCommunityWall,
    bool? goesToSubscriptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedDelivery(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      contentType: contentType ?? this.contentType,
      goesToMainFeed: goesToMainFeed ?? this.goesToMainFeed,
      goesToReelsFeed: goesToReelsFeed ?? this.goesToReelsFeed,
      goesToCommunityWall: goesToCommunityWall ?? this.goesToCommunityWall,
      goesToSubscriptions: goesToSubscriptions ?? this.goesToSubscriptions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

