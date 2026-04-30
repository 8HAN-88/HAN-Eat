import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

/// Модель комментария
class PostComment {
  final String id;
  final String postId;
  final String authorId;
  final String? authorName;
  final String? authorAvatar;
  final String text;
  final String? parentCommentId; // Для ответов
  final DateTime createdAt;
  final int likes;
  final bool isDeleted;

  PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.authorName,
    this.authorAvatar,
    required this.text,
    this.parentCommentId,
    required this.createdAt,
    this.likes = 0,
    this.isDeleted = false,
  });

  factory PostComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostComment(
      id: doc.id,
      postId: data['postId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String?,
      authorAvatar: data['authorAvatar'] as String?,
      text: data['text'] as String? ?? '',
      parentCommentId: data['parentCommentId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likes: data['likes'] as int? ?? 0,
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'postId': postId,
      'authorId': authorId,
      if (authorName != null) 'authorName': authorName,
      if (authorAvatar != null) 'authorAvatar': authorAvatar,
      'text': text,
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      'createdAt': Timestamp.fromDate(createdAt),
      'likes': likes,
      'isDeleted': isDeleted,
    };
  }
}

/// Сервис для работы с комментариями к постам
class PostCommentsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Добавить комментарий
  static Future<String> addComment(
    String postId,
    String text, {
    String? parentCommentId,
  }) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final commentRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc();

      final comment = PostComment(
        id: commentRef.id,
        postId: postId,
        authorId: currentUser.uid,
        authorName: currentUser.name,
        authorAvatar: currentUser.avatarUrl,
        text: text,
        parentCommentId: parentCommentId,
        createdAt: DateTime.now(),
      );

      await commentRef.set(comment.toFirestore());

      // Увеличиваем счётчик комментариев
      await _firestore.collection('posts').doc(postId).update({
        'reactions.comments': FieldValue.increment(1),
      });

      return commentRef.id;
    } catch (e) {
      print('Error adding comment: $e');
      rethrow;
    }
  }

  /// Получить комментарии к посту
  static Stream<List<PostComment>> getComments(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .where('isDeleted', isEqualTo: false)
        .where('parentCommentId', isNull: true) // Только основные комментарии
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostComment.fromFirestore(doc))
            .toList());
  }

  /// Получить ответы на комментарий
  static Stream<List<PostComment>> getCommentReplies(String postId, String parentCommentId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .where('parentCommentId', isEqualTo: parentCommentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostComment.fromFirestore(doc))
            .toList());
  }

  /// Лайкнуть комментарий
  static Future<void> likeComment(String postId, String commentId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final likeRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .collection('likes')
          .doc(currentUser.uid);

      final snapshot = await likeRef.get();
      if (snapshot.exists) {
        await likeRef.delete();
        await _firestore
            .collection('posts')
            .doc(postId)
            .collection('comments')
            .doc(commentId)
            .update({'likes': FieldValue.increment(-1)});
      } else {
        await likeRef.set({'createdAt': FieldValue.serverTimestamp()});
        await _firestore
            .collection('posts')
            .doc(postId)
            .collection('comments')
            .doc(commentId)
            .update({'likes': FieldValue.increment(1)});
      }
    } catch (e) {
      print('Error liking comment: $e');
      rethrow;
    }
  }

  /// Удалить комментарий
  static Future<void> deleteComment(String postId, String commentId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('User not authenticated');

    try {
      final commentDoc = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .get();

      final comment = PostComment.fromFirestore(commentDoc);
      if (comment.authorId != currentUser.uid) {
        throw Exception('Only author can delete comment');
      }

      // Мягкое удаление
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .update({'isDeleted': true});

      // Уменьшаем счётчик комментариев
      await _firestore.collection('posts').doc(postId).update({
        'reactions.comments': FieldValue.increment(-1),
      });
    } catch (e) {
      print('Error deleting comment: $e');
      rethrow;
    }
  }

  /// Проверить, лайкнут ли комментарий
  static Stream<bool> isCommentLikedStream(String postId, String commentId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return Stream.value(false);

    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .collection('likes')
        .doc(currentUser.uid)
        .snapshots()
        .map((doc) => doc.exists);
  }
}

