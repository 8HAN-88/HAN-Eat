class StoryAuthor {
  const StoryAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;

  factory StoryAuthor.fromJson(Map<String, dynamic> json) => StoryAuthor(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Пользователь',
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class StoryReactionSummary {
  const StoryReactionSummary({
    required this.emoji,
    required this.count,
  });

  final String emoji;
  final int count;

  factory StoryReactionSummary.fromJson(Map<String, dynamic> json) =>
      StoryReactionSummary(
        emoji: json['emoji'] as String? ?? '',
        count: json['count'] as int? ?? 0,
      );
}

class StoryDto {
  const StoryDto({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    required this.visibility,
    required this.viewsCount,
    required this.createdAt,
    required this.expiresAt,
    required this.author,
    this.thumbnailUrl,
    this.caption,
    this.reactions = const [],
    this.myReaction,
  });

  final int id;
  final int userId;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String mediaType;
  final String? caption;
  final String visibility;
  final int viewsCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StoryAuthor author;
  final List<StoryReactionSummary> reactions;
  final String? myReaction;

  bool get isVideo => mediaType == 'video';
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory StoryDto.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'] as List<dynamic>? ?? const [];
    return StoryDto(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      mediaUrl: json['media_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mediaType: json['media_type'] as String? ?? 'image',
      caption: json['caption'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      viewsCount: json['views_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      author: StoryAuthor.fromJson(json['author'] as Map<String, dynamic>),
      reactions: rawReactions
          .whereType<Map<String, dynamic>>()
          .map(StoryReactionSummary.fromJson)
          .where((e) => e.emoji.isNotEmpty)
          .toList(),
      myReaction: json['my_reaction'] as String?,
    );
  }

  StoryDto copyWith({
    int? viewsCount,
    List<StoryReactionSummary>? reactions,
    String? myReaction,
    bool clearMyReaction = false,
  }) {
    return StoryDto(
      id: id,
      userId: userId,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      mediaType: mediaType,
      caption: caption,
      visibility: visibility,
      viewsCount: viewsCount ?? this.viewsCount,
      createdAt: createdAt,
      expiresAt: expiresAt,
      author: author,
      reactions: reactions ?? this.reactions,
      myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
    );
  }
}

class StoryViewerDto {
  const StoryViewerDto({
    required this.user,
    required this.viewedAt,
    this.reaction,
  });

  final StoryAuthor user;
  final DateTime viewedAt;
  final String? reaction;

  factory StoryViewerDto.fromJson(Map<String, dynamic> json) => StoryViewerDto(
        user: StoryAuthor.fromJson(json['user'] as Map<String, dynamic>),
        viewedAt: DateTime.parse(json['viewed_at'] as String).toLocal(),
        reaction: json['reaction'] as String?,
      );
}

class StoryViewersPage {
  const StoryViewersPage({
    required this.viewsCount,
    required this.items,
  });

  final int viewsCount;
  final List<StoryViewerDto> items;

  factory StoryViewersPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return StoryViewersPage(
      viewsCount: json['views_count'] as int? ?? 0,
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(StoryViewerDto.fromJson)
          .toList(),
    );
  }
}

class StoryGroup {
  const StoryGroup({
    required this.author,
    required this.stories,
  });

  final StoryAuthor author;
  final List<StoryDto> stories;

  StoryDto get latest => stories.first;
}

class StoryCreateRequest {
  const StoryCreateRequest({
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.caption,
    this.visibility = 'public',
  });

  final String mediaUrl;
  final String? thumbnailUrl;
  final String mediaType;
  final String? caption;
  final String visibility;

  Map<String, dynamic> toJson() => {
        'media_url': mediaUrl,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        'media_type': mediaType,
        if (caption != null && caption!.trim().isNotEmpty)
          'caption': caption!.trim(),
        'visibility': visibility,
      };
}
