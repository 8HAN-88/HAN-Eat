import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель сообщества
class Community {
  final String id;
  final String name;
  final String? avatar;
  final String? cover;
  final String? description;
  final String ownerId;
  final String category; // Тематика из еды
  final DateTime createdAt;
  final CommunitySettings settings;
  final int membersCount;
  final int postsCount;
  final bool isVerified;

  Community({
    required this.id,
    required this.name,
    this.avatar,
    this.cover,
    this.description,
    required this.ownerId,
    required this.category,
    required this.createdAt,
    required this.settings,
    this.membersCount = 0,
    this.postsCount = 0,
    this.isVerified = false,
  });

  factory Community.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Community(
      id: doc.id,
      name: data['name'] as String? ?? '',
      avatar: data['avatar'] as String?,
      cover: data['cover'] as String?,
      description: data['description'] as String?,
      ownerId: data['ownerId'] as String? ?? '',
      category: data['category'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      settings: CommunitySettings.fromMap(data['settings'] as Map<String, dynamic>? ?? {}),
      membersCount: data['membersCount'] as int? ?? 0,
      postsCount: data['postsCount'] as int? ?? 0,
      isVerified: data['isVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      if (avatar != null) 'avatar': avatar,
      if (cover != null) 'cover': cover,
      if (description != null) 'description': description,
      'ownerId': ownerId,
      'category': category,
      'createdAt': Timestamp.fromDate(createdAt),
      'settings': settings.toMap(),
      'membersCount': membersCount,
      'postsCount': postsCount,
      'isVerified': isVerified,
    };
  }

  Community copyWith({
    String? id,
    String? name,
    String? avatar,
    String? cover,
    String? description,
    String? ownerId,
    String? category,
    DateTime? createdAt,
    CommunitySettings? settings,
    int? membersCount,
    int? postsCount,
    bool? isVerified,
  }) {
    return Community(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      cover: cover ?? this.cover,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      settings: settings ?? this.settings,
      membersCount: membersCount ?? this.membersCount,
      postsCount: postsCount ?? this.postsCount,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

/// Настройки сообщества
class CommunitySettings {
  final bool commentsEnabled;
  final bool messagesEnabled;
  final String? website;
  final String? vkLink;
  final String? instagramLink;
  final String? telegramLink;
  final String? youtubeLink;
  final Map<String, dynamic> additionalSettings;

  CommunitySettings({
    this.commentsEnabled = true,
    this.messagesEnabled = true,
    this.website,
    this.vkLink,
    this.instagramLink,
    this.telegramLink,
    this.youtubeLink,
    Map<String, dynamic>? additionalSettings,
  }) : additionalSettings = additionalSettings ?? {};

  factory CommunitySettings.fromMap(Map<String, dynamic> map) {
    return CommunitySettings(
      commentsEnabled: map['commentsEnabled'] as bool? ?? true,
      messagesEnabled: map['messagesEnabled'] as bool? ?? true,
      website: map['website'] as String?,
      vkLink: map['vkLink'] as String?,
      instagramLink: map['instagramLink'] as String?,
      telegramLink: map['telegramLink'] as String?,
      youtubeLink: map['youtubeLink'] as String?,
      additionalSettings: Map<String, dynamic>.from(map['additionalSettings'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'commentsEnabled': commentsEnabled,
      'messagesEnabled': messagesEnabled,
      if (website != null) 'website': website,
      if (vkLink != null) 'vkLink': vkLink,
      if (instagramLink != null) 'instagramLink': instagramLink,
      if (telegramLink != null) 'telegramLink': telegramLink,
      if (youtubeLink != null) 'youtubeLink': youtubeLink,
      if (additionalSettings.isNotEmpty) 'additionalSettings': additionalSettings,
    };
  }

  CommunitySettings copyWith({
    bool? commentsEnabled,
    bool? messagesEnabled,
    String? website,
    String? vkLink,
    String? instagramLink,
    String? telegramLink,
    String? youtubeLink,
    Map<String, dynamic>? additionalSettings,
  }) {
    return CommunitySettings(
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
      messagesEnabled: messagesEnabled ?? this.messagesEnabled,
      website: website ?? this.website,
      vkLink: vkLink ?? this.vkLink,
      instagramLink: instagramLink ?? this.instagramLink,
      telegramLink: telegramLink ?? this.telegramLink,
      youtubeLink: youtubeLink ?? this.youtubeLink,
      additionalSettings: additionalSettings ?? this.additionalSettings,
    );
  }
}

/// Роли в сообществе
enum CommunityRole {
  owner, // Владелец
  admin, // Администратор
  editor, // Редактор
  moderator, // Модератор
  member, // Обычный участник
}

/// Права ролей
class RolePermissions {
  final bool canCreatePosts;
  final bool canPublishReels;
  final bool canModerateComments;
  final bool canChangeSettings;
  final bool canInviteAdmins;
  final bool canDeletePosts;
  final bool canPinPosts;
  final bool canHidePosts;

  RolePermissions({
    required this.canCreatePosts,
    required this.canPublishReels,
    required this.canModerateComments,
    required this.canChangeSettings,
    required this.canInviteAdmins,
    required this.canDeletePosts,
    required this.canPinPosts,
    required this.canHidePosts,
  });

  static RolePermissions forRole(CommunityRole role) {
    switch (role) {
      case CommunityRole.owner:
        return RolePermissions(
          canCreatePosts: true,
          canPublishReels: true,
          canModerateComments: true,
          canChangeSettings: true,
          canInviteAdmins: true,
          canDeletePosts: true,
          canPinPosts: true,
          canHidePosts: true,
        );
      case CommunityRole.admin:
        return RolePermissions(
          canCreatePosts: true,
          canPublishReels: true,
          canModerateComments: true,
          canChangeSettings: true,
          canInviteAdmins: true,
          canDeletePosts: true,
          canPinPosts: true,
          canHidePosts: true,
        );
      case CommunityRole.editor:
        return RolePermissions(
          canCreatePosts: true,
          canPublishReels: true,
          canModerateComments: false,
          canChangeSettings: false,
          canInviteAdmins: false,
          canDeletePosts: false,
          canPinPosts: false,
          canHidePosts: false,
        );
      case CommunityRole.moderator:
        return RolePermissions(
          canCreatePosts: false,
          canPublishReels: false,
          canModerateComments: true,
          canChangeSettings: false,
          canInviteAdmins: false,
          canDeletePosts: false,
          canPinPosts: false,
          canHidePosts: true,
        );
      case CommunityRole.member:
        return RolePermissions(
          canCreatePosts: false,
          canPublishReels: false,
          canModerateComments: false,
          canChangeSettings: false,
          canInviteAdmins: false,
          canDeletePosts: false,
          canPinPosts: false,
          canHidePosts: false,
        );
    }
  }
}

/// Участник сообщества
class CommunityMember {
  final String userId;
  final String communityId;
  final CommunityRole role;
  final DateTime joinedAt;
  final String? invitedBy;

  CommunityMember({
    required this.userId,
    required this.communityId,
    required this.role,
    required this.joinedAt,
    this.invitedBy,
  });

  factory CommunityMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityMember(
      userId: data['userId'] as String? ?? '',
      communityId: data['communityId'] as String? ?? '',
      role: _parseRole(data['role'] as String?),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      invitedBy: data['invitedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'communityId': communityId,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      if (invitedBy != null) 'invitedBy': invitedBy,
    };
  }

  static CommunityRole _parseRole(String? role) {
    switch (role) {
      case 'owner':
        return CommunityRole.owner;
      case 'admin':
        return CommunityRole.admin;
      case 'editor':
        return CommunityRole.editor;
      case 'moderator':
        return CommunityRole.moderator;
      default:
        return CommunityRole.member;
    }
  }

  RolePermissions get permissions => RolePermissions.forRole(role);
}

