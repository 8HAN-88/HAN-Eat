import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../core/config/legacy_firestore_config.dart';
import 'moderation_log_service.dart';

/// Legacy Firestore community videos — не используется в основном V2 flow.
@Deprecated('Community reels use Postgres API (ApiService.fetchCommunityVideos)')
class CommunityService {
  static bool _isFirebaseInitialized() {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool get _useFirestore =>
      LegacyFirestoreConfig.enabled && _isFirebaseInitialized();

  static Stream<int> likeCountStream(String videoDocId) {
    if (!_useFirestore) {
      return Stream.value(0);
    }
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('likes')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          debugPrint('Error in likeCountStream: $error');
          return 0;
        });
  }

  static Stream<int> commentsCountStream(String videoDocId) {
    if (!_useFirestore) {
      return Stream.value(0);
    }
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('comments')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          debugPrint('Error in commentsCountStream: $error');
          return 0;
        });
  }

  static Stream<bool> isLikedStream(String videoDocId, String? uid) {
    if (uid == null || !_useFirestore) return Stream.value(false);
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((error) {
          debugPrint('Error in isLikedStream: $error');
          return false;
        });
  }

  static Future<void> toggleLike(String videoDocId, String uid) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot toggle like');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('likes')
          .doc(uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.delete();
      } else {
        await docRef.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  static Stream<QuerySnapshot> commentsStream(String videoDocId) {
    // Всегда используем реальный запрос - он безопасен и вернет пустой результат если нет данных
    // Обрабатываем ошибки gracefully
    try {
      return FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .handleError((error) {
            debugPrint('Error in commentsStream: $error');
            // При ошибке возвращаем пустой stream через запрос limit(0)
            try {
              return FirebaseFirestore.instance
                  .collection('community_videos')
                  .doc(videoDocId)
                  .collection('comments')
                  .limit(0)
                  .snapshots();
            } catch (e) {
              debugPrint('Error in commentsStream fallback: $e');
              // Если и это не работает, возвращаем пустой stream
              final controller = StreamController<QuerySnapshot>();
              Future.microtask(() async {
                try {
                  final emptySnapshot = await FirebaseFirestore.instance
                      .collection('community_videos')
                      .doc(videoDocId)
                      .collection('comments')
                      .limit(0)
                      .get();
                  if (!controller.isClosed) {
                    controller.add(emptySnapshot);
                    await controller.close();
                  }
                } catch (err) {
                  debugPrint('Error in commentsStream final fallback: $err');
                  if (!controller.isClosed) {
                    await controller.close();
                  }
                }
              });
              return controller.stream;
            }
          });
    } catch (e) {
      debugPrint('Error creating commentsStream: $e');
      // Возвращаем пустой stream при любой ошибке
      final controller = StreamController<QuerySnapshot>();
      controller.close();
      return controller.stream;
    }
  }

  static Future<void> addComment(String videoDocId, String uid, String text,
      {String status = 'published', String? parentCommentId}) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot add comment');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .add({
        'authorId': uid,
        'text': text,
        // Локальный timestamp помогает увидеть комментарий сразу в UI
        // (без задержки, пока сервер подтвердит serverTimestamp).
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'status': status,
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
      });
    } catch (e) {
      debugPrint('Error adding comment: $e');
      rethrow;
    }
  }

  // Лайки комментариев
  static Stream<int> commentLikesStream(String videoDocId, String commentId) {
    if (!_useFirestore) {
      return Stream.value(0);
    }
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('comments')
        .doc(commentId)
        .collection('likes')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          debugPrint('Error in commentLikesStream: $error');
          return 0;
        });
  }

  static Stream<bool> isCommentLikedStream(
      String videoDocId, String commentId, String? uid) {
    if (uid == null || !_useFirestore) return Stream.value(false);
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('comments')
        .doc(commentId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((error) {
          debugPrint('Error in isCommentLikedStream: $error');
          return false;
        });
  }

  static Future<void> toggleCommentLike(
      String videoDocId, String commentId, String uid) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot toggle comment like');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .doc(commentId)
          .collection('likes')
          .doc(uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.delete();
      } else {
        await docRef.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Error toggling comment like: $e');
    }
  }

  // Ответы на комментарии
  static Stream<QuerySnapshot> commentRepliesStream(
      String videoDocId, String parentCommentId) {
    // Всегда используем реальный запрос - он безопасен и вернет пустой результат если нет данных
    try {
      return FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .where('parentCommentId', isEqualTo: parentCommentId)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .handleError((error) {
            debugPrint('Error in commentRepliesStream: $error');
            // При ошибке возвращаем пустой stream через запрос limit(0)
            try {
              return FirebaseFirestore.instance
                  .collection('community_videos')
                  .doc(videoDocId)
                  .collection('comments')
                  .limit(0)
                  .snapshots();
            } catch (e) {
              debugPrint('Error in commentRepliesStream fallback: $e');
              // Если и это не работает, возвращаем пустой stream
              final controller = StreamController<QuerySnapshot>();
              Future.microtask(() async {
                try {
                  final emptySnapshot = await FirebaseFirestore.instance
                      .collection('community_videos')
                      .doc(videoDocId)
                      .collection('comments')
                      .limit(0)
                      .get();
                  if (!controller.isClosed) {
                    controller.add(emptySnapshot);
                    await controller.close();
                  }
                } catch (err) {
                  debugPrint('Error in commentRepliesStream final fallback: $err');
                  if (!controller.isClosed) {
                    await controller.close();
                  }
                }
              });
              return controller.stream;
            }
          });
    } catch (e) {
      debugPrint('Error creating commentRepliesStream: $e');
      // Возвращаем пустой stream при любой ошибке
      final controller = StreamController<QuerySnapshot>();
      controller.close();
      return controller.stream;
    }
  }

  // Репорт комментария (Firestore community)
  static Future<void> reportComment(
    String videoDocId,
    String commentId,
    String uid, {
    String reason = 'other',
    String? comment,
  }) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot report comment');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .doc(commentId)
          .collection('reports')
          .doc(uid)
          .set({
        'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error reporting comment: $e');
      rethrow;
    }
  }

  static Future<void> setVideoStatus(String videoDocId, String status) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot set video status');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId);
      await docRef.update({'status': status});
      await ModerationLogService.log(
          'setVideoStatus', {'videoId': videoDocId, 'status': status});
    } catch (e) {
      debugPrint('Error setting video status: $e');
    }
  }

  // Soft delete (mark as deleted)
  static Future<void> softDeleteVideo(String videoDocId) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot soft delete video');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId);
      await docRef.update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
      });
      await ModerationLogService.log('softDeleteVideo', {'videoId': videoDocId});
    } catch (e) {
      debugPrint('Error soft deleting video: $e');
    }
  }

  // Restore a soft-deleted video back to published
  static Future<void> restoreVideo(String videoDocId) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot restore video');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId);
      await docRef.update({
        'status': 'published',
        'deletedAt': FieldValue.delete(),
      });
      await ModerationLogService.log('restoreVideo', {'videoId': videoDocId});
    } catch (e) {
      debugPrint('Error restoring video: $e');
    }
  }

  // Permanently delete the video and its subcollections
  static Future<void> permanentlyDeleteVideo(String videoDocId) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot permanently delete video');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId);

      // delete subcollections (likes, comments) - simple approach for demo
      final likesSnap = await docRef.collection('likes').get();
      for (final d in likesSnap.docs) {
        await d.reference.delete();
      }
      final commentsSnap = await docRef.collection('comments').get();
      for (final d in commentsSnap.docs) {
        await d.reference.delete();
      }

      // optionally delete storage file is out of scope here
      await docRef.delete();
      await ModerationLogService.log(
          'permanentlyDeleteVideo', {'videoId': videoDocId});
    } catch (e) {
      debugPrint('Error permanently deleting video: $e');
    }
  }

  static Future<void> setCommentStatus(
      String videoDocId, String commentDocId, String status) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot set comment status');
      return;
    }
    try {
      final commentRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .doc(commentDocId);
      await commentRef.update({'status': status});
      await ModerationLogService.log('setCommentStatus',
          {'videoId': videoDocId, 'commentId': commentDocId, 'status': status});
    } catch (e) {
      debugPrint('Error setting comment status: $e');
    }
  }

  static Future<void> deleteComment(
      String videoDocId, String commentDocId) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot delete comment');
      return;
    }
    try {
      final commentRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('comments')
          .doc(commentDocId);
      await commentRef.delete();
      await ModerationLogService.log(
          'deleteComment', {'videoId': videoDocId, 'commentId': commentDocId});
    } catch (e) {
      debugPrint('Error deleting comment: $e');
    }
  }

  // Репорт видео (Firestore community; для API-рилсов используйте ReportService)
  static Future<void> reportVideo(
    String videoDocId,
    String uid, {
    String reason = 'other',
    String? comment,
  }) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot report video');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('reports')
          .doc(uid)
          .set({
        'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await ModerationLogService.log('reportVideo', {
        'videoId': videoDocId,
        'reporterUid': uid,
        'reason': reason,
        if (comment != null) 'comment': comment,
      });
    } catch (e) {
      debugPrint('Error reporting video: $e');
      rethrow;
    }
  }

  // Репосты видео
  static Stream<int> repostCountStream(String videoDocId) {
    if (!_useFirestore) {
      return Stream.value(0);
    }
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('reposts')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          debugPrint('Error in repostCountStream: $error');
          return 0;
        });
  }

  static Stream<bool> isRepostedStream(String videoDocId, String? uid) {
    if (uid == null || !_useFirestore) return Stream.value(false);
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('reposts')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((error) {
          debugPrint('Error in isRepostedStream: $error');
          return false;
        });
  }

  static Future<void> toggleRepost(String videoDocId, String uid) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot toggle repost');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('reposts')
          .doc(uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.delete();
      } else {
        await docRef.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Error toggling repost: $e');
    }
  }

  // Сохранение видео (bookmark)
  static Stream<int> saveCountStream(String videoDocId) {
    if (!_useFirestore) {
      return Stream.value(0);
    }
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('saves')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          debugPrint('Error in saveCountStream: $error');
          return 0;
        });
  }

  static Stream<bool> isSavedStream(String videoDocId, String? uid) {
    if (uid == null || !_useFirestore) return Stream.value(false);
    return FirebaseFirestore.instance
        .collection('community_videos')
        .doc(videoDocId)
        .collection('saves')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((error) {
          debugPrint('Error in isSavedStream: $error');
          return false;
        });
  }

  static Future<void> toggleSave(String videoDocId, String uid) async {
    if (!_useFirestore) {
      debugPrint('Firebase not initialized, cannot toggle save');
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .collection('saves')
          .doc(uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.delete();
      } else {
        await docRef.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Error toggling save: $e');
    }
  }
}
