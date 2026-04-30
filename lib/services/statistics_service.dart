import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/community.dart';
import 'auth_service.dart';

/// Статистика поста
class PostStatistics {
  final int views;
  final int likes;
  final int dislikes;
  final int comments;
  final int shares;
  final int saves;
  final double engagementRate; // Процент вовлечённости

  PostStatistics({
    this.views = 0,
    this.likes = 0,
    this.dislikes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.engagementRate = 0.0,
  });

  factory PostStatistics.fromMap(Map<String, dynamic> map) {
    final views = map['views'] as int? ?? 0;
    final totalEngagement = (map['likes'] as int? ?? 0) +
        (map['comments'] as int? ?? 0) +
        (map['shares'] as int? ?? 0);
    final engagementRate = views > 0 ? (totalEngagement / views) * 100 : 0.0;

    return PostStatistics(
      views: views,
      likes: map['likes'] as int? ?? 0,
      dislikes: map['dislikes'] as int? ?? 0,
      comments: map['comments'] as int? ?? 0,
      shares: map['shares'] as int? ?? 0,
      saves: map['saves'] as int? ?? 0,
      engagementRate: engagementRate,
    );
  }
}

/// Статистика сообщества
class CommunityStatistics {
  final int membersCount;
  final int postsCount;
  final int totalViews;
  final int totalLikes;
  final int totalComments;
  final double averageEngagement;
  final Map<String, int> postsByType; // По типам постов
  final List<PostStatistics> topPosts;

  CommunityStatistics({
    this.membersCount = 0,
    this.postsCount = 0,
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.averageEngagement = 0.0,
    Map<String, int>? postsByType,
    this.topPosts = const [],
  }) : postsByType = postsByType ?? {};

  factory CommunityStatistics.fromMap(Map<String, dynamic> map) {
    return CommunityStatistics(
      membersCount: map['membersCount'] as int? ?? 0,
      postsCount: map['postsCount'] as int? ?? 0,
      totalViews: map['totalViews'] as int? ?? 0,
      totalLikes: map['totalLikes'] as int? ?? 0,
      totalComments: map['totalComments'] as int? ?? 0,
      averageEngagement: (map['averageEngagement'] as num?)?.toDouble() ?? 0.0,
      postsByType: Map<String, int>.from(map['postsByType'] as Map? ?? {}),
      topPosts: (map['topPosts'] as List<dynamic>?)
              ?.map((p) => PostStatistics.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Сервис для получения статистики
class StatisticsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Получить статистику поста
  static Future<PostStatistics> getPostStatistics(String postId) async {
    try {
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) throw Exception('Post not found');

      final post = Post.fromFirestore(postDoc);
      final reactions = post.reactions;

      // Получаем количество сохранений
      final savesSnapshot = await _firestore
          .collection('users')
          .doc('_') // Заглушка, нужно использовать другой подход
          .collection('savedPosts')
          .where('postId', isEqualTo: postId)
          .count()
          .get();

      // Альтернативный способ - подсчитать через все пользователи
      int saves = 0;
      try {
        final allUsers = await _firestore.collection('users').limit(1000).get();
        for (final userDoc in allUsers.docs) {
          final savedDoc = await _firestore
              .collection('users')
              .doc(userDoc.id)
              .collection('savedPosts')
              .doc(postId)
              .get();
          if (savedDoc.exists) saves++;
        }
      } catch (e) {
        // Если не удалось подсчитать, оставляем 0
      }

      // Получаем количество дизлайков
      final dislikesSnapshot = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('dislikes')
          .count()
          .get();

      final dislikes = dislikesSnapshot.count ?? 0;

      return PostStatistics(
        views: reactions.views,
        likes: reactions.likes,
        dislikes: dislikes,
        comments: reactions.comments,
        shares: reactions.shares,
        saves: saves,
        engagementRate: reactions.views > 0
            ? ((reactions.likes + reactions.comments + reactions.shares) /
                    reactions.views) *
                100
            : 0.0,
      );
    } catch (e) {
      print('Error getting post statistics: $e');
      rethrow;
    }
  }

  /// Получить статистику сообщества
  static Future<CommunityStatistics> getCommunityStatistics(String communityId) async {
    try {
      final communityDoc = await _firestore
          .collection('communities')
          .doc(communityId)
          .get();
      if (!communityDoc.exists) throw Exception('Community not found');

      final community = Community.fromFirestore(communityDoc);

      // Получаем все посты сообщества
      final postsSnapshot = await _firestore
          .collection('posts')
          .where('communityId', isEqualTo: communityId)
          .where('isDeleted', isEqualTo: false)
          .get();

      final posts = postsSnapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();

      // Подсчитываем статистику
      int totalViews = 0;
      int totalLikes = 0;
      int totalComments = 0;
      final postsByType = <String, int>{};
      final postStats = <PostStatistics>[];

      for (final post in posts) {
        totalViews += post.reactions.views;
        totalLikes += post.reactions.likes;
        totalComments += post.reactions.comments;

        final type = post.type; // type уже String
        postsByType[type] = (postsByType[type] ?? 0) + 1;

        postStats.add(PostStatistics(
          views: post.reactions.views,
          likes: post.reactions.likes,
          comments: post.reactions.comments,
          shares: post.reactions.shares,
          engagementRate: post.reactions.views > 0
              ? ((post.reactions.likes + post.reactions.comments + post.reactions.shares) /
                      post.reactions.views) *
                  100
              : 0.0,
        ));
      }

      // Сортируем по вовлечённости и берём топ-5
      postStats.sort((a, b) => b.engagementRate.compareTo(a.engagementRate));
      final topPosts = postStats.take(5).toList();

      final averageEngagement = posts.isNotEmpty
          ? postStats.map((s) => s.engagementRate).reduce((a, b) => a + b) / posts.length
          : 0.0;

      return CommunityStatistics(
        membersCount: community.membersCount,
        postsCount: community.postsCount,
        totalViews: totalViews,
        totalLikes: totalLikes,
        totalComments: totalComments,
        averageEngagement: averageEngagement,
        postsByType: postsByType,
        topPosts: topPosts,
      );
    } catch (e) {
      print('Error getting community statistics: $e');
      rethrow;
    }
  }

  /// Увеличить счётчик просмотров
  static Future<void> incrementViews(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'reactions.views': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error incrementing views: $e');
    }
  }

  /// Получить статистику пользователя
  static Future<Map<String, dynamic>> getUserStatistics(String userId) async {
    try {
      // Количество постов
      final postsSnapshot = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .count()
          .get();

      final postsCount = postsSnapshot.count ?? 0;

      // Общее количество лайков
      final posts = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();

      int totalLikes = 0;
      int totalViews = 0;
      for (final doc in posts.docs) {
        final post = Post.fromFirestore(doc);
        totalLikes += post.reactions.likes;
        totalViews += post.reactions.views;
      }

      // Количество подписчиков
      int followersCount = 0;
      try {
        final followersSnapshot = await _firestore
            .collection('users')
            .doc('_') // Заглушка
            .collection('following')
            .where(FieldPath.documentId, isEqualTo: userId)
            .count()
            .get();
        
        // Альтернативный способ
        final allUsers = await _firestore.collection('users').limit(1000).get();
        for (final userDoc in allUsers.docs) {
          final followingDoc = await _firestore
              .collection('users')
              .doc(userDoc.id)
              .collection('following')
              .doc(userId)
              .get();
          if (followingDoc.exists) followersCount++;
        }
      } catch (e) {
        // Если не удалось подсчитать, оставляем 0
      }

      return {
        'postsCount': postsCount,
        'totalLikes': totalLikes,
        'totalViews': totalViews,
        'followersCount': followersCount,
      };
    } catch (e) {
      print('Error getting user statistics: $e');
      return {};
    }
  }
}

