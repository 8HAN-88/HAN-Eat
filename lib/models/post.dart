// Модель поста для нового API
import 'package:json_annotation/json_annotation.dart';

part 'post.g.dart';

@JsonSerializable()
class Post {
  final int id;
  final String type; // text | photo | recipe | reel
  final String? title;
  final String? description;
  final String status;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'published_at')
  final DateTime? publishedAt;
  @JsonKey(name: 'user_id')
  final int userId;
  @JsonKey(name: 'community_id')
  final int? communityId;
  @JsonKey(name: 'channel_id')
  final int? channelId; // Для обратной совместимости
  final Map<String, dynamic>? body;
  final List<String>? tags;
  
  // Метаданные
  @JsonKey(name: 'likes_count')
  final int likesCount;
  @JsonKey(name: 'comments_count')
  final int commentsCount;
  @JsonKey(name: 'reposts_count')
  final int? repostsCount;
  @JsonKey(name: 'is_liked')
  final bool isLiked;
  final PostAuthor? author;
  
  Post({
    required this.id,
    required this.type,
    this.title,
    this.description,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    required this.userId,
    this.communityId,
    this.channelId,
    this.body,
    this.tags,
    required this.likesCount,
    required this.commentsCount,
    this.repostsCount,
    required this.isLiked,
    this.author,
  });
  
  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);
  Map<String, dynamic> toJson() => _$PostToJson(this);
  
  // Геттеры для доступа к данным из body
  String? get text => body?['text'] as String? ?? description;
  List<String>? get photos {
    // Сначала проверяем старый формат
    final photos = body?['photos'];
    if (photos is List) {
      return photos.map((e) => e.toString()).toList();
    }
    // Затем проверяем новый формат в media массиве
    final media = body?['media'];
    if (media is List) {
      final imageUrls = <String>[];
      for (final item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'image') {
          final url = item['url'] as String?;
          if (url != null) {
            imageUrls.add(url);
          }
        }
      }
      if (imageUrls.isNotEmpty) {
        return imageUrls;
      }
    }
    return null;
  }
  String? get videoUrl {
    // Сначала проверяем старый формат
    if (body?['video_url'] != null) {
      return body!['video_url'] as String?;
    }
    // Затем проверяем новый формат в media массиве
    final media = body?['media'];
    if (media is List) {
      for (final item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'video') {
          return item['url'] as String?;
        }
      }
    }
    return null;
  }
  
  String? get videoThumbnail {
    // Сначала проверяем старый формат
    if (body?['video_thumbnail'] != null) {
      return body!['video_thumbnail'] as String?;
    }
    // Затем проверяем новый формат в media массиве
    final media = body?['media'];
    if (media is List) {
      for (final item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'video') {
          return item['thumbnail_url'] as String?;
        }
      }
    }
    return null;
  }
  String? get linkUrl => body?['link_url'] as String?;
  String? get linkPreview => body?['link_preview'] as String?;
  PollData? get poll {
    final pollData = body?['poll'];
    if (pollData is Map<String, dynamic>) {
      try {
        return PollData.fromJson(pollData);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
  Post? get repostedPost {
    final reposted = body?['reposted_post'];
    if (reposted is Map<String, dynamic>) {
      try {
        return Post.fromJson(reposted);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
  PostReactions get reactions => PostReactions(
    likes: likesCount,
    comments: commentsCount,
    shares: repostsCount ?? 0,
    views: (body?['views'] as num?)?.toInt() ?? 0,
    dislikes: (body?['dislikes'] as num?)?.toInt() ?? 0,
  );
  bool get isAd => body?['is_ad'] as bool? ?? false;
  bool get isPinned => body?['is_pinned'] as bool? ?? false;
  
  // Геттеры для автора
  String? get authorId => author?.id.toString() ?? userId.toString();
  String? get authorName => author?.name;
  String? get authorAvatar => author?.avatarUrl;
  String? get groupId => body?['group_id'] as String? ?? communityId?.toString();
  String? get groupName => body?['group_name'] as String?;
  String? get groupAvatar => body?['group_avatar'] as String?;
  String? get location => body?['location'] as String?;
  String? get language => body?['language'] as String?;
  bool get isPromoted => body?['is_promoted'] as bool? ?? false;
  
  // Геттер для строкового id (для совместимости)
  String get idString => id.toString();
  
  // Метод для создания из Firestore (заглушка)
  factory Post.fromFirestore(dynamic doc) {
    if (doc is Map<String, dynamic>) {
      return Post.fromJson(doc);
    }
    // Если doc имеет метод data(), используем его
    try {
      final data = (doc as dynamic).data() as Map<String, dynamic>?;
      if (data != null) {
        return Post.fromJson(data);
      }
    } catch (e) {
      // Игнорируем ошибки
    }
    throw Exception('Cannot create Post from Firestore document');
  }
}

/// Реакции на пост
class PostReactions {
  final int likes;
  final int comments;
  final int shares;
  final int views;
  final int dislikes;
  
  PostReactions({
    required this.likes,
    required this.comments,
    required this.shares,
    required this.views,
    this.dislikes = 0,
  });
}

/// Данные опроса
class PollData {
  final String question;
  final List<PollOption> options;
  
  PollData({
    required this.question,
    required this.options,
  });
  
  factory PollData.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>?)
        ?.map((e) => PollOption.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    return PollData(
      question: json['question'] as String? ?? '',
      options: options,
    );
  }
}

/// Вариант ответа в опросе
class PollOption {
  final String text;
  final int votes;
  final double percentage;
  
  PollOption({
    required this.text,
    required this.votes,
    required this.percentage,
  });
  
  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      text: json['text'] as String? ?? '',
      votes: json['votes'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

@JsonSerializable()
class PostAuthor {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  PostAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  factory PostAuthor.fromJson(Map<String, dynamic> json) => _$PostAuthorFromJson(json);
  Map<String, dynamic> toJson() => _$PostAuthorToJson(this);
}
