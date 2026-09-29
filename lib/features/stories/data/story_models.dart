int _storyJsonInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

String? _storyJsonString(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

DateTime? _storyJsonDate(Object? raw) {
  if (raw is DateTime) return raw.toLocal();
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw.trim())?.toLocal();
  }
  return null;
}

Map<String, dynamic>? _storyJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

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
        id: _storyJsonInt(json['id']),
        name: _storyJsonString(json['name']) ?? 'Пользователь',
        username: _storyJsonString(json['username']),
        avatarUrl: _storyJsonString(json['avatar_url']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'avatar_url': avatarUrl,
      };
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
        emoji: _storyJsonString(json['emoji']) ?? '',
        count: _storyJsonInt(json['count']),
      );

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
      };
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
    final createdAt = _storyJsonDate(json['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final expiresAt = _storyJsonDate(json['expires_at']) ??
        createdAt.add(const Duration(hours: 24));
    final authorMap = _storyJsonMap(json['author']);
    return StoryDto(
      id: _storyJsonInt(json['id']),
      userId: _storyJsonInt(json['user_id']),
      mediaUrl: _storyJsonString(json['media_url']) ?? '',
      thumbnailUrl: _storyJsonString(json['thumbnail_url']),
      mediaType: _storyJsonString(json['media_type']) ?? 'image',
      caption: _storyJsonString(json['caption']),
      visibility: _storyJsonString(json['visibility']) ?? 'public',
      viewsCount: _storyJsonInt(json['views_count']),
      createdAt: createdAt,
      expiresAt: expiresAt,
      author: StoryAuthor.fromJson(authorMap ?? const {}),
      reactions: rawReactions
          .whereType<Map>()
          .map((e) => StoryReactionSummary.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.emoji.isNotEmpty)
          .toList(),
      myReaction: _storyJsonString(json['my_reaction']),
    );
  }

  bool get isPlayable => id > 0 && mediaUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'media_url': mediaUrl,
        'thumbnail_url': thumbnailUrl,
        'media_type': mediaType,
        'caption': caption,
        'visibility': visibility,
        'views_count': viewsCount,
        'created_at': createdAt.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'author': author.toJson(),
        'reactions': reactions.map((e) => e.toJson()).toList(),
        'my_reaction': myReaction,
      };

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
        user: StoryAuthor.fromJson(_storyJsonMap(json['user']) ?? const {}),
        viewedAt: _storyJsonDate(json['viewed_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        reaction: _storyJsonString(json['reaction']),
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
      viewsCount: _storyJsonInt(json['views_count']),
      items: raw
          .whereType<Map>()
          .map((e) => StoryViewerDto.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.user.id > 0)
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
