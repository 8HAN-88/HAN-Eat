import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/community.dart';
import '../models/post.dart';
import 'auth_service.dart';

/// Сервис для управления сообществами
class CommunityManagementService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Создать сообщество
  static Future<Community> createCommunity({
    required String name,
    required String category,
    String? description,
    String? avatarPath,
    String? coverPath,
    Uint8List? avatarBytes,
    Uint8List? coverBytes,
    CommunitySettings? settings,
  }) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Загружаем аватар и обложку, если они есть
      String? avatarUrl;
      String? coverUrl;

      if (avatarPath != null || avatarBytes != null) {
        avatarUrl = await _uploadImage(
          avatarPath,
          'avatars',
          bytes: avatarBytes,
        );
      }

      if (coverPath != null || coverBytes != null) {
        coverUrl = await _uploadImage(
          coverPath,
          'covers',
          bytes: coverBytes,
        );
      }

      // Создаём документ сообщества
      final communityRef = _firestore.collection('communities').doc();
      final community = Community(
        id: communityRef.id,
        name: name,
        avatar: avatarUrl,
        cover: coverUrl,
        description: description,
        ownerId: currentUser.uid,
        category: category,
        createdAt: DateTime.now(),
        settings: settings ?? CommunitySettings(),
      );

      await communityRef.set(community.toFirestore());

      // Добавляем владельца как участника с ролью owner
      await _firestore
          .collection('community_members')
          .doc('${currentUser.uid}_${communityRef.id}')
          .set(CommunityMember(
            userId: currentUser.uid,
            communityId: communityRef.id,
            role: CommunityRole.owner,
            joinedAt: DateTime.now(),
          ).toFirestore());

      // Обновляем счётчик участников
      await communityRef.update({'membersCount': FieldValue.increment(1)});

      return community;
    } catch (e) {
      print('Error creating community: $e');
      rethrow;
    }
  }

  /// Загрузить изображение
  static Future<String> _uploadImage(
    String? localPath,
    String folder, {
    Uint8List? bytes,
  }) async {
    try {
      final fileName = localPath != null
          ? '${DateTime.now().millisecondsSinceEpoch}_${localPath.split('/').last}'
          : '${DateTime.now().millisecondsSinceEpoch}_image.jpg';
      
      final ref = _storage.ref().child('communities/$folder/$fileName');
      
      if (kIsWeb && bytes != null) {
        // На вебе используем bytes
        final uploadTask = ref.putData(bytes);
        await uploadTask;
      } else if (localPath != null) {
        // На других платформах используем File
        final file = File(localPath);
        if (!await file.exists()) {
          throw Exception('File does not exist: $localPath');
        }
        final uploadTask = ref.putFile(file);
        await uploadTask;
      } else {
        throw Exception('No file path or bytes provided');
      }
      
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      rethrow;
    }
  }

  /// Обновить настройки сообщества
  static Future<void> updateCommunitySettings(
    String communityId,
    CommunitySettings settings,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Проверяем права
    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canChangeSettings) {
      throw Exception('Insufficient permissions');
    }

    await _firestore.collection('communities').doc(communityId).update({
      'settings': settings.toMap(),
    });
  }

  /// Обновить аватар сообщества
  static Future<void> updateAvatar(String communityId, String imagePath) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canChangeSettings) {
      throw Exception('Insufficient permissions');
    }

    final avatarUrl = await _uploadImage(imagePath, 'avatars');
    await _firestore.collection('communities').doc(communityId).update({
      'avatar': avatarUrl,
    });
  }

  /// Обновить обложку сообщества
  static Future<void> updateCover(String communityId, String imagePath) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canChangeSettings) {
      throw Exception('Insufficient permissions');
    }

    final coverUrl = await _uploadImage(imagePath, 'covers');
    await _firestore.collection('communities').doc(communityId).update({
      'cover': coverUrl,
    });
  }

  /// Обновить описание сообщества
  static Future<void> updateDescription(
    String communityId,
    String description,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canChangeSettings) {
      throw Exception('Insufficient permissions');
    }

    await _firestore.collection('communities').doc(communityId).update({
      'description': description,
    });
  }

  /// Получить сообщество
  static Future<Community?> getCommunity(String communityId) async {
    try {
      final doc = await _firestore.collection('communities').doc(communityId).get();
      if (!doc.exists) return null;
      return Community.fromFirestore(doc);
    } catch (e) {
      print('Error getting community: $e');
      return null;
    }
  }

  /// Получить участника сообщества
  static Future<CommunityMember?> getCommunityMember(
    String communityId,
    String userId,
  ) async {
    try {
      final doc = await _firestore
          .collection('community_members')
          .doc('${userId}_$communityId')
          .get();
      if (!doc.exists) return null;
      return CommunityMember.fromFirestore(doc);
    } catch (e) {
      print('Error getting community member: $e');
      return null;
    }
  }

  /// Пригласить администратора
  static Future<void> inviteAdmin(
    String communityId,
    String userId,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canInviteAdmins) {
      throw Exception('Insufficient permissions');
    }

    // Добавляем пользователя как администратора
    await _firestore
        .collection('community_members')
        .doc('${userId}_$communityId')
        .set(CommunityMember(
          userId: userId,
          communityId: communityId,
          role: CommunityRole.admin,
          joinedAt: DateTime.now(),
          invitedBy: currentUser.uid,
        ).toFirestore());

    // Обновляем счётчик участников
    await _firestore.collection('communities').doc(communityId).update({
      'membersCount': FieldValue.increment(1),
    });
  }

  /// Изменить роль участника
  static Future<void> changeMemberRole(
    String communityId,
    String userId,
    CommunityRole newRole,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member == null || !member.permissions.canInviteAdmins) {
      throw Exception('Insufficient permissions');
    }

    await _firestore
        .collection('community_members')
        .doc('${userId}_$communityId')
        .update({'role': newRole.name});
  }

  /// Подписаться на сообщество
  static Future<void> subscribeToCommunity(String communityId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Проверяем, не подписан ли уже
    final existing = await getCommunityMember(communityId, currentUser.uid);
    if (existing != null) {
      return; // Уже подписан
    }

    // Добавляем как обычного участника
    await _firestore
        .collection('community_members')
        .doc('${currentUser.uid}_$communityId')
        .set(CommunityMember(
          userId: currentUser.uid,
          communityId: communityId,
          role: CommunityRole.member,
          joinedAt: DateTime.now(),
        ).toFirestore());

    // Обновляем счётчик участников
    await _firestore.collection('communities').doc(communityId).update({
      'membersCount': FieldValue.increment(1),
    });
  }

  /// Отписаться от сообщества
  static Future<void> unsubscribeFromCommunity(String communityId) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final member = await getCommunityMember(communityId, currentUser.uid);
    if (member?.role == CommunityRole.owner) {
      throw Exception('Owner cannot unsubscribe');
    }

    await _firestore
        .collection('community_members')
        .doc('${currentUser.uid}_$communityId')
        .delete();

    // Обновляем счётчик участников
    await _firestore.collection('communities').doc(communityId).update({
      'membersCount': FieldValue.increment(-1),
    });
  }

  /// Получить список сообществ пользователя
  static Future<List<Community>> getUserCommunities(String userId) async {
    try {
      final membersSnapshot = await _firestore
          .collection('community_members')
          .where('userId', isEqualTo: userId)
          .get();

      if (membersSnapshot.docs.isEmpty) return [];

      final communityIds = membersSnapshot.docs
          .map((doc) => doc.data()['communityId'] as String)
          .toList();

      final communities = <Community>[];
      for (var i = 0; i < communityIds.length; i += 10) {
        final batch = communityIds.skip(i).take(10).toList();
        final snapshot = await _firestore
            .collection('communities')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        communities.addAll(
          snapshot.docs.map((doc) => Community.fromFirestore(doc)),
        );
      }

      return communities;
    } catch (e) {
      print('Error getting user communities: $e');
      return [];
    }
  }

  /// Получить стену сообщества
  static Stream<List<Post>> getCommunityWall(String communityId) {
    return _firestore
        .collection('posts')
        .where('communityId', isEqualTo: communityId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('isPinned', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Post.fromFirestore(doc))
            .toList());
  }

  /// Поиск сообществ
  static Future<List<Community>> searchCommunities(String query) async {
    try {
      // Firestore не поддерживает полнотекстовый поиск, используем простой фильтр
      final snapshot = await _firestore
          .collection('communities')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      return snapshot.docs.map((doc) => Community.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error searching communities: $e');
      return [];
    }
  }
}

