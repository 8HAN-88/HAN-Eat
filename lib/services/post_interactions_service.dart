import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/post_types.dart';
import 'auth_service.dart';

/// Сервис для взаимодействий с постами (лайки, дизлайки, репосты, сохранения)
class PostInteractionsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Лайкнуть пост
  static Future<void> likePost(String postId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final likeRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('likes')
          .doc(currentUser.uid);

      final snapshot = await likeRef.get();
      if (snapshot.exists) {
        // Убираем лайк
        await likeRef.delete();
        await _firestore.collection('posts').doc(postId).update({
          'reactions.likes': FieldValue.increment(-1),
        });
      } else {
        // Ставим лайк
        await likeRef.set({'createdAt': FieldValue.serverTimestamp()});
        await _firestore.collection('posts').doc(postId).update({
          'reactions.likes': FieldValue.increment(1),
        });

        // Убираем дизлайк, если был
        final dislikeRef = _firestore
            .collection('posts')
            .doc(postId)
            .collection('dislikes')
            .doc(currentUser.uid);
        final dislikeSnapshot = await dislikeRef.get();
        if (dislikeSnapshot.exists) {
          await dislikeRef.delete();
          await _firestore.collection('posts').doc(postId).update({
            'reactions.dislikes': FieldValue.increment(-1),
          });
        }
      }
    } catch (e) {
      print('Error liking post: $e');
      rethrow;
    }
  }

  /// Дизлайкнуть пост
  static Future<void> dislikePost(String postId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final dislikeRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('dislikes')
          .doc(currentUser.uid);

      final snapshot = await dislikeRef.get();
      if (snapshot.exists) {
        // Убираем дизлайк
        await dislikeRef.delete();
        await _firestore.collection('posts').doc(postId).update({
          'reactions.dislikes': FieldValue.increment(-1),
        });
      } else {
        // Ставим дизлайк
        await dislikeRef.set({'createdAt': FieldValue.serverTimestamp()});
        await _firestore.collection('posts').doc(postId).update({
          'reactions.dislikes': FieldValue.increment(1),
        });

        // Убираем лайк, если был
        final likeRef = _firestore
            .collection('posts')
            .doc(postId)
            .collection('likes')
            .doc(currentUser.uid);
        final likeSnapshot = await likeRef.get();
        if (likeSnapshot.exists) {
          await likeRef.delete();
          await _firestore.collection('posts').doc(postId).update({
            'reactions.likes': FieldValue.increment(-1),
          });
        }
      }
    } catch (e) {
      print('Error disliking post: $e');
      rethrow;
    }
  }

  /// Проверить, лайкнут ли пост
  static Stream<bool> isLikedStream(String postId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return Stream.value(false);

    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(currentUser.uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Проверить, дизлайкнут ли пост
  static Stream<bool> isDislikedStream(String postId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return Stream.value(false);

    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('dislikes')
        .doc(currentUser.uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Репостнуть пост
  static Future<void> repostPost(String postId, {String? text}) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      // Получаем оригинальный пост
      final originalPostDoc = await _firestore.collection('posts').doc(postId).get();
      if (!originalPostDoc.exists) throw Exception('Post not found');

      final originalPost = Post.fromFirestore(originalPostDoc);

      // Создаём репост
      final repostRef = _firestore.collection('posts').doc();
      final repostId = int.tryParse(repostRef.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? DateTime.now().millisecondsSinceEpoch;
      final repost = Post(
        id: repostId,
        type: PostType.repost.value,
        status: PostStatus.published.value,
        createdAt: DateTime.now(),
        userId: int.tryParse(currentUser.uid) ?? 0,
        likesCount: 0,
        commentsCount: 0,
        isLiked: false,
        body: {
          if (text != null) 'text': text,
          'reposted_post': originalPost.toJson(),
        },
        tags: originalPost.tags,
        author: PostAuthor(
          id: int.tryParse(currentUser.uid) ?? 0,
          name: currentUser.name,
          avatarUrl: currentUser.avatarUrl,
        ),
      );

      await repostRef.set(repost.toJson());

      // Увеличиваем счётчик репостов оригинального поста
      await _firestore.collection('posts').doc(postId).update({
        'reactions.shares': FieldValue.increment(1),
      });

      // Настраиваем доставку репоста
      await _firestore.collection('feed_delivery').add({
        'postId': repostRef.id,
        'contentType': 'post',
        'goesToMainFeed': true,
        'goesToReelsFeed': false,
        'goesToCommunityWall': false,
        'goesToSubscriptions': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error reposting: $e');
      rethrow;
    }
  }

  /// Сохранить пост
  static Future<void> savePost(String postId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final saveRef = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('savedPosts')
          .doc(postId);

      final snapshot = await saveRef.get();
      if (snapshot.exists) {
        // Убираем из сохранённых
        await saveRef.delete();
      } else {
        // Сохраняем
        await saveRef.set({
          'postId': postId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error saving post: $e');
      rethrow;
    }
  }

  /// Проверить, сохранён ли пост
  static Stream<bool> isSavedStream(String postId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return Stream.value(false);

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('savedPosts')
        .doc(postId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Получить сохранённые посты
  static Stream<List<Post>> getSavedPosts() {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('savedPosts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((savedSnapshot) async {
      if (savedSnapshot.docs.isEmpty) return <Post>[];

      final postIds = savedSnapshot.docs.map((doc) => doc.data()['postId'] as String).toList();
      final posts = <Post>[];

      for (var i = 0; i < postIds.length; i += 10) {
        final batch = postIds.skip(i).take(10).toList();
        final postsSnapshot = await _firestore
            .collection('posts')
            .where(FieldPath.documentId, whereIn: batch)
            .where('isDeleted', isEqualTo: false)
            .get();

        posts.addAll(postsSnapshot.docs.map((doc) => Post.fromFirestore(doc)));
      }

      return posts;
    });
  }

  /// Получить количество лайков
  static Stream<int> likesCountStream(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Получить количество дизлайков
  static Stream<int> dislikesCountStream(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('dislikes')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}

