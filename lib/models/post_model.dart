// Модель поста для нового API (без code generation пока)
import 'post.dart';

class PostModel {
  final int id;
  final String type; // text | photo | recipe | reel
  final String? title;
  final String? description;
  final String status;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final int userId;
  final int? communityId;
  final Map<String, dynamic>? body;
  final List<String>? tags;
  
  // Геттер для обратной совместимости (channelId = communityId)
  int? get channelId => communityId;
  
  // Метаданные
  final int likesCount;
  final int commentsCount;
  final int repostsCount;
  final int viewsCount;  // Счетчик просмотров
  final bool isLiked;
  final bool? isSaved;
  final bool? isReposted;
  final PostAuthorModel? author;
  final PostAuthorModel? repostedBy;  // Информация о том, кто репостнул
  final ChannelModel? channel;  // Информация о канале (если пост из канала)
  
  PostModel({
    required this.id,
    required this.type,
    this.title,
    this.description,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    required this.userId,
    this.communityId,
    this.body,
    this.tags,
    required this.likesCount,
    required this.commentsCount,
    required this.repostsCount,
    required this.viewsCount,
    required this.isLiked,
    this.isSaved,
    this.isReposted,
    this.author,
    this.repostedBy,
    this.channel,
  });
  
  factory PostModel.fromJson(Map<String, dynamic> json) {
    // Обрабатываем ID - может быть int или строка вида "spoonacular_123"
    int parsedId;
    if (json['id'] is int) {
      parsedId = json['id'] as int;
    } else if (json['id'] is String) {
      final idStr = json['id'] as String;
      if (idStr.startsWith('spoonacular_')) {
        // Для рецептов Spoonacular используем числовую часть
        final numPart = idStr.replaceFirst('spoonacular_', '');
        parsedId = int.tryParse(numPart) ?? 0;
      } else {
        parsedId = int.tryParse(idStr) ?? 0;
      }
    } else {
      parsedId = 0;
    }
    
    final createdAtRaw = json['created_at'];
    final createdAt = createdAtRaw != null && createdAtRaw is String
        ? DateTime.parse(createdAtRaw)
        : DateTime.fromMillisecondsSinceEpoch(0);

    return PostModel(
      id: parsedId,
      type: json['type'] as String? ?? 'text',
      title: json['title'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'published',
      createdAt: createdAt,
      publishedAt: json['published_at'] != null && json['published_at'] is String
          ? DateTime.parse(json['published_at'] as String)
          : null,
      userId: json['user_id'] as int,
      communityId: json['community_id'] as int? ?? json['channel_id'] as int?, // Поддержка channel_id
      body: json['body'] as Map<String, dynamic>?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      repostsCount: json['reposts_count'] as int? ?? 0,
      viewsCount: json['views_count'] as int? ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
      isSaved: json['is_saved'] as bool?,
      isReposted: json['is_reposted'] as bool?,
      author: json['author'] != null
          ? PostAuthorModel.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      repostedBy: json['reposted_by'] != null
          ? PostAuthorModel.fromJson(json['reposted_by'] as Map<String, dynamic>)
          : null,
      channel: json['channel'] != null
          ? ChannelModel.fromJson(json['channel'] as Map<String, dynamic>)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
      'user_id': userId,
      'community_id': communityId,
      'body': body,
      'tags': tags,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'reposts_count': repostsCount,
      'views_count': viewsCount,
      'is_liked': isLiked,
      'is_saved': isSaved,
      'is_reposted': isReposted,
      'author': author?.toJson(),
      'reposted_by': repostedBy?.toJson(),
      'channel': channel?.toJson(),
    };
  }
  
  /// Преобразовать PostModel в Post
  Post toPost() {
    return Post(
      id: id,
      type: type,
      title: title,
      description: description,
      status: status,
      createdAt: createdAt,
      publishedAt: publishedAt,
      userId: userId,
      communityId: communityId,
      body: body,
      tags: tags,
      likesCount: likesCount,
      commentsCount: commentsCount,
      repostsCount: repostsCount,
      isLiked: isLiked,
      author: author != null
          ? PostAuthor(
              id: author!.id,
              name: author!.name,
              username: author!.username,
              avatarUrl: author!.avatarUrl,
            )
          : null,
    );
  }
}

class PostAuthorModel {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  PostAuthorModel({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  factory PostAuthorModel.fromJson(Map<String, dynamic> json) {
    return PostAuthorModel(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'avatar_url': avatarUrl,
    };
  }
}

class ChannelModel {
  final int id;
  final String name;
  final String slug;
  final String? avatarUrl;
  final String? coverUrl;
  final String? description;
  
  ChannelModel({
    required this.id,
    required this.name,
    required this.slug,
    this.avatarUrl,
    this.coverUrl,
    this.description,
  });
  
  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      avatarUrl: json['avatar_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      description: json['description'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'avatar_url': avatarUrl,
      'cover_url': coverUrl,
      'description': description,
    };
  }
}

