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

  bool get isVideo => mediaType == 'video';
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory StoryDto.fromJson(Map<String, dynamic> json) => StoryDto(
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
      );
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
