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
  @JsonKey(name: 'is_saved', defaultValue: false)
  final bool isSaved;
  /// Серверное продвижение в ленте (Firestore может дублировать в body).
  @JsonKey(name: 'is_promoted')
  final bool isPromotedFromApi;
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
    required this.isSaved,
    this.isPromotedFromApi = false,
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
  Map<String, dynamic>? get linkMeta {
    final raw = body?['link_meta'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  String? get linkTitle => linkMeta?['title'] as String? ?? linkPreview;
  String? get linkDescription => linkMeta?['description'] as String?;
  String? get linkImage => linkMeta?['image'] as String?;
  String? get linkDomain => linkMeta?['domain'] as String?;

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

  /// Продвижение: REST-поле и/или legacy в body (Firestore).
  bool get isPromoted =>
      isPromotedFromApi || (body?['is_promoted'] as bool? ?? false);

  // Геттеры для автора
  String? get authorId => author?.id.toString() ?? userId.toString();
  String? get authorName => author?.name;
  String? get authorAvatar => author?.avatarUrl;
  String? get groupId => body?['group_id'] as String? ?? communityId?.toString();
  String? get groupName => body?['group_name'] as String?;
  String? get groupAvatar => body?['group_avatar'] as String?;
  String? get location => body?['location'] as String?;
  String? get language => body?['language'] as String?;

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
  /// Индекс варианта, за который проголосовал текущий пользователь (если есть).
  final int? votedOptionIndex;
  final bool isClosed;

  PollData({
    required this.question,
    required this.options,
    this.votedOptionIndex,
    this.isClosed = false,
  });

  bool get hasVoted => votedOptionIndex != null;

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'options': options
          .map(
            (o) => {
              'text': o.text,
              'votes': o.votes,
              'percentage': o.percentage,
              'index': o.index,
            },
          )
          .toList(),
      'is_closed': isClosed,
      if (votedOptionIndex != null) 'voted_option_index': votedOptionIndex,
    };
  }

  factory PollData.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>?)
            ?.map((e) => PollOption.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return PollData(
      question: json['question'] as String? ?? '',
      options: options,
      votedOptionIndex: json['voted_option_index'] as int?,
      isClosed: json['is_closed'] as bool? ?? false,
    );
  }
}

/// Вариант ответа в опросе
class PollOption {
  final String text;
  final int votes;
  final double percentage;
  final int index;

  PollOption({
    required this.text,
    required this.votes,
    required this.percentage,
    this.index = 0,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      text: json['text'] as String? ?? '',
      votes: json['votes'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      index: json['index'] as int? ?? 0,
    );
  }
}

class PollVoter {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;

  PollVoter({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  factory PollVoter.fromJson(Map<String, dynamic> json) {
    return PollVoter(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class PollVotersOption {
  final int index;
  final String text;
  final List<PollVoter> voters;

  PollVotersOption({
    required this.index,
    required this.text,
    required this.voters,
  });

  factory PollVotersOption.fromJson(Map<String, dynamic> json) {
    final voters = (json['voters'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PollVoter.fromJson)
        .toList();
    return PollVotersOption(
      index: (json['index'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      voters: voters,
    );
  }
}

class PollVotersResponse {
  final List<PollVotersOption> options;
  final int total;

  PollVotersResponse({
    required this.options,
    required this.total,
  });

  factory PollVotersResponse.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PollVotersOption.fromJson)
        .toList();
    return PollVotersResponse(
      options: options,
      total: (json['total'] as num?)?.toInt() ?? 0,
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
