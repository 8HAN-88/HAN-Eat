import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/post.dart';
import '../models/post_types.dart';
import '../models/reel.dart';
import 'auth_service.dart';
import 'feed_delivery_service.dart';
import 'community_management_service.dart';
import 'package:flutter/foundation.dart';

import 'legacy_firestore_guard.dart';

/// Сервис для публикации постов и рилсов
class PostPublicationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Опубликовать пост
  static Future<String> publishPost({
    required String? communityId,
    required PostType type,
    String? text,
    List<String>? photos,
    String? videoUrl,
    String? videoThumbnail,
    String? linkUrl,
    String? linkPreview,
    PollData? poll,
    List<String>? tags,
    String? location,
  }) async {
    LegacyFirestoreGuard.ensureEnabled();
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Если пост для сообщества, проверяем права
    if (communityId != null) {
      final member = await CommunityManagementService.getCommunityMember(
        communityId,
        currentUser.uid,
      );
      if (member == null || !member.permissions.canCreatePosts) {
        throw Exception('Insufficient permissions to create posts');
      }
    }

    try {
      // Получаем информацию о сообществе, если есть
      String? communityName;
      String? communityAvatar;
      if (communityId != null) {
        final community = await CommunityManagementService.getCommunity(communityId);
        communityName = community?.name;
        communityAvatar = community?.avatar;
      }

      // Создаём пост
      final postRef = _firestore.collection('posts').doc();
      final postId = DateTime.now().millisecondsSinceEpoch; // Временный ID
      
      // Собираем body для Post модели
      final body = <String, dynamic>{};
      if (text != null) body['text'] = text;
      if (photos != null && photos.isNotEmpty) body['photos'] = photos;
      if (videoUrl != null) body['video_url'] = videoUrl;
      if (videoThumbnail != null) body['video_thumbnail'] = videoThumbnail;
      if (linkUrl != null) body['link_url'] = linkUrl;
      if (linkPreview != null) body['link_preview'] = linkPreview;
      if (poll != null) {
        body['poll'] = {
          'question': poll.question,
          'options': poll.options.map((o) => {
            'text': o.text,
            'votes': o.votes,
            'percentage': o.percentage,
          }).toList(),
        };
      }
      if (communityName != null) body['group_name'] = communityName;
      if (communityAvatar != null) body['group_avatar'] = communityAvatar;
      
      // Сохраняем в Firestore
      await postRef.set({
        'id': postId,
        'type': type.value,
        'description': text,
        'status': PostStatus.published.value,
        'created_at': FieldValue.serverTimestamp(),
        'user_id': currentUser.uid,
        'community_id': communityId,
        'body': body,
        'tags': tags ?? [],
        'likes_count': 0,
        'comments_count': 0,
        'is_liked': false,
        'author': {
          'id': currentUser.uid,
          'name': currentUser.name,
          'avatar_url': currentUser.avatarUrl,
        },
      });

      // Настраиваем доставку контента
      await FeedDeliveryService.createDelivery(
        postId: postRef.id,
        contentType: 'post',
        goesToMainFeed: true, // Посты попадают в общую ленту
        goesToReelsFeed: false,
        goesToCommunityWall: communityId != null, // Если из сообщества - на стену
        goesToSubscriptions: true, // Подписчикам
      );

      // Обновляем счётчик постов сообщества
      if (communityId != null) {
        await _firestore.collection('communities').doc(communityId).update({
          'postsCount': FieldValue.increment(1),
        });
      }

      return postRef.id;
    } catch (e) {
      debugPrint('Error publishing post: $e');
      rethrow;
    }
  }

  /// Загрузить фото поста в Firebase Storage (порядок сохраняется).
  static Future<List<String>> uploadPostImages({
    List<File>? files,
    List<Uint8List>? imageBytes,
  }) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    final uid = currentUser.uid;
    final urls = <String>[];
    final baseMs = DateTime.now().millisecondsSinceEpoch;

    if (files != null && files.isNotEmpty) {
      var i = 0;
      for (final file in files) {
        if (!await file.exists()) continue;
        final ref = _storage.ref().child('posts/$uid/${baseMs}_$i.jpg');
        await ref.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        urls.add(await ref.getDownloadURL());
        i++;
      }
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      var i = 0;
      for (final bytes in imageBytes) {
        if (bytes.isEmpty) continue;
        final ref = _storage.ref().child('posts/$uid/${baseMs}_$i.jpg');
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        urls.add(await ref.getDownloadURL());
        i++;
      }
    }

    if (urls.isEmpty &&
        ((files?.isNotEmpty ?? false) || (imageBytes?.isNotEmpty ?? false))) {
      throw Exception('Не удалось загрузить изображения');
    }
    return urls;
  }

  /// Опубликовать рилс
  static Future<String> publishReel({
    required String communityId,
    required String videoPath,
    String? description,
    List<String>? tags,
  }) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Проверяем права на публикацию рилсов
    final member = await CommunityManagementService.getCommunityMember(
      communityId,
      currentUser.uid,
    );
    if (member == null || !member.permissions.canPublishReels) {
      throw Exception('Insufficient permissions to publish reels');
    }

    try {
      // Загружаем видео
      final videoUrls = await _uploadVideo(videoPath);

      // Создаём рилс
      final reelRef = _firestore.collection('reels').doc();
      final reel = Reel(
        id: reelRef.id,
        communityId: communityId,
        authorId: currentUser.uid,
        urlOriginal: videoUrls['original']!,
        urlTranscoded: videoUrls['transcoded'] ?? videoUrls['original']!,
        description: description,
        tags: tags ?? [],
        createdAt: DateTime.now(),
      );

      await reelRef.set(reel.toFirestore());

      // Создаём пост-рилс для отображения на стене сообщества
      final community = await CommunityManagementService.getCommunity(communityId);
      final postRef = _firestore.collection('posts').doc();
      final postId = DateTime.now().millisecondsSinceEpoch;
      
      final body = <String, dynamic>{
        'text': description,
        'video_url': reel.urlTranscoded,
      };
      if (community?.name != null) body['group_name'] = community!.name;
      if (community?.avatar != null) body['group_avatar'] = community!.avatar;
      
      await postRef.set({
        'id': postId,
        'type': PostType.reel.value,
        'description': description,
        'status': PostStatus.published.value,
        'created_at': FieldValue.serverTimestamp(),
        'user_id': currentUser.uid,
        'community_id': communityId,
        'body': body,
        'tags': tags ?? [],
        'likes_count': 0,
        'comments_count': 0,
        'is_liked': false,
        'author': {
          'id': currentUser.uid,
          'name': currentUser.name,
          'avatar_url': currentUser.avatarUrl,
        },
      });

      // Настраиваем доставку контента для рилса
      // Рилы попадают ВСЮДУ: стена, общая лента, лента рилсов, подписки
      await FeedDeliveryService.createDelivery(
        postId: reelRef.id,
        contentType: 'reel',
        goesToMainFeed: true, // В общую ленту
        goesToReelsFeed: true, // В ленту рилсов
        goesToCommunityWall: true, // На стену сообщества
        goesToSubscriptions: true, // Подписчикам
      );

      // Также создаём доставку для поста-рилса на стене
      await FeedDeliveryService.createDelivery(
        postId: postRef.id,
        contentType: 'post',
        goesToMainFeed: false, // Пост-рилс не дублируется в общей ленте
        goesToReelsFeed: false,
        goesToCommunityWall: true, // Только на стену
        goesToSubscriptions: false,
      );

      // Обновляем счётчик постов сообщества
      await _firestore.collection('communities').doc(communityId).update({
        'postsCount': FieldValue.increment(1),
      });

      return reelRef.id;
    } catch (e) {
      debugPrint('Error publishing reel: $e');
      rethrow;
    }
  }

  /// Загрузить видео
  static Future<Map<String, String>> _uploadVideo(String localPath) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${localPath.split('/').last}';
      
      // Загружаем оригинальное видео
      final originalRef = _storage.ref().child('reels/original/$fileName');
      await originalRef.putFile(File(localPath));
      final originalUrl = await originalRef.getDownloadURL();

      // В реальном приложении здесь будет транскодирование видео
      // Для демо используем оригинальное видео
      final transcodedUrl = originalUrl;

      return {
        'original': originalUrl,
        'transcoded': transcodedUrl,
      };
    } catch (e) {
      debugPrint('Error uploading video: $e');
      rethrow;
    }
  }

  /// Закрепить пост
  static Future<void> pinPost(String postId, String communityId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await CommunityManagementService.getCommunityMember(
      communityId,
      currentUser.uid,
    );
    if (member == null || !member.permissions.canPinPosts) {
      throw Exception('Insufficient permissions to pin posts');
    }

    // Снимаем закрепление с других постов
    final pinnedPosts = await _firestore
        .collection('posts')
        .where('communityId', isEqualTo: communityId)
        .where('isPinned', isEqualTo: true)
        .get();

    for (final doc in pinnedPosts.docs) {
      await doc.reference.update({'isPinned': false});
    }

    // Закрепляем новый пост
    await _firestore.collection('posts').doc(postId).update({'isPinned': true});
  }

  /// Снять закрепление поста
  static Future<void> unpinPost(String postId) async {
    await _firestore.collection('posts').doc(postId).update({'isPinned': false});
  }

  /// Скрыть пост
  static Future<void> hidePost(String postId, String communityId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await CommunityManagementService.getCommunityMember(
      communityId,
      currentUser.uid,
    );
    if (member == null || !member.permissions.canHidePosts) {
      throw Exception('Insufficient permissions to hide posts');
    }

    await _firestore.collection('posts').doc(postId).update({'isDeleted': true});
  }

  /// Удалить пост
  static Future<void> deletePost(String postId, String? communityId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Проверяем права, если пост из сообщества
    if (communityId != null) {
      final member = await CommunityManagementService.getCommunityMember(
        communityId,
        currentUser.uid,
      );
      if (member == null || !member.permissions.canDeletePosts) {
        throw Exception('Insufficient permissions to delete posts');
      }
    } else {
      // Личный пост - только автор может удалить
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      final postData = postDoc.data();
      if (postData?['authorId'] != currentUser.uid) {
        throw Exception('Only author can delete their post');
      }
    }

    await _firestore.collection('posts').doc(postId).update({'isDeleted': true});

    // Обновляем счётчик постов сообщества
    if (communityId != null) {
      await _firestore.collection('communities').doc(communityId).update({
        'postsCount': FieldValue.increment(-1),
      });
    }
  }
}

