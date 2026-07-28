// Модель поста для нового API (без code generation пока)
import '../models/video_quality_preference.dart';
import '../services/reel_video_sources.dart';
import '../services/server_config.dart';
import 'post.dart';

class PostCommentPreview {
  const PostCommentPreview({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.text,
  });

  final int id;
  final int userId;
  final String authorName;
  final String text;

  factory PostCommentPreview.fromJson(Map<String, dynamic> json) {
    return PostCommentPreview(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      authorName: json['author_name'] as String? ?? 'Пользователь',
      text: (json['text'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'author_name': authorName,
        'text': text,
      };
}

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
  final List<PostCommentPreview> previewComments;
  final int repostsCount;
  final int viewsCount;  // Счетчик просмотров
  final bool isPromoted;
  final bool isPinned;
  final bool isExclusive;
  final bool isPaid;
  final int priceStars;
  final String previewMode;
  final bool purchased;
  final bool isLiked;
  final bool? isSaved;
  final bool? isReposted;
  final PostAuthorModel? author;
  final PostAuthorModel? repostedBy;  // Информация о том, кто репостнул
  final ChannelModel? channel;  // Информация о канале (если пост из канала)
  /// public | private | followers — для рецептов в канале
  final String visibility;

  bool get isPrivateRecipe => type == 'recipe' && visibility == 'private';

  PollData? get poll {
    final pollData = body?['poll'];
    if (pollData is Map<String, dynamic>) {
      try {
        return PollData.fromJson(pollData);
      } catch (_) {
        return null;
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

  /// Все варианты видео (HLS, 480p, 720p, оригинал).
  ReelVideoSources get reelVideoSources => ReelVideoSources.fromPostBody(body);

  /// URL для быстрого старта (режим «Авто») — обратная совместимость.
  String? get videoUrl =>
      reelVideoSources.fastStartUrl(VideoQualityPreference.auto);

  String? videoUrlFor(VideoQualityPreference pref) =>
      reelVideoSources.fastStartUrl(pref);

  String? get videoThumbnail {
    final direct = body?['video_thumbnail'];
    if (direct is String && direct.trim().isNotEmpty) {
      return ServerConfig.resolveMediaUrl(direct.trim());
    }
    final media = body?['media'];
    if (media is List) {
      for (final item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'video') {
          final t = item['thumbnail_url'] ?? item['thumbnail'];
          if (t is String && t.trim().isNotEmpty) {
            return ServerConfig.resolveMediaUrl(t.trim());
          }
        }
      }
    }
    return null;
  }

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
    this.previewComments = const [],
    required this.repostsCount,
    required this.viewsCount,
    this.isPromoted = false,
    this.isPinned = false,
    this.isExclusive = false,
    this.isPaid = false,
    this.priceStars = 0,
    this.previewMode = 'teaser',
    this.purchased = true,
    required this.isLiked,
    this.isSaved,
    this.isReposted,
    this.author,
    this.repostedBy,
    this.channel,
    this.visibility = 'public',
  });
  
  /// Обратное преобразование из [Post] (например для обновления оффлайн-кеша ленты).
  factory PostModel.fromPost(Post p) {
    return PostModel(
      id: p.id,
      type: p.type,
      title: p.title,
      description: p.description,
      status: p.status,
      createdAt: p.createdAt,
      publishedAt: p.publishedAt,
      userId: p.userId,
      communityId: p.communityId ?? p.channelId,
      body: p.body,
      tags: p.tags,
      likesCount: p.likesCount,
      commentsCount: p.commentsCount,
      previewComments: const [],
      repostsCount: p.repostsCount ?? 0,
      viewsCount: p.reactions.views,
      isPromoted: p.isPromoted,
      isPaid: false,
      priceStars: 0,
      previewMode: 'teaser',
      purchased: true,
      isLiked: p.isLiked,
      isSaved: p.isSaved,
      isReposted: null,
      author: p.author != null
          ? PostAuthorModel(
              id: p.author!.id,
              name: p.author!.name,
              username: p.author!.username,
              avatarUrl: p.author!.avatarUrl,
              comment: null,
            )
          : null,
      repostedBy: null,
      channel: p.channelId != null
          ? ChannelModel(
              id: p.channelId!,
              name: (p.body?['channel_name'] as String?)?.trim().isNotEmpty ==
                      true
                  ? (p.body!['channel_name'] as String).trim()
                  : 'Канал',
              slug: '',
              avatarUrl: p.body?['channel_avatar'] as String?,
            )
          : null,
    );
  }

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
      } else if (idStr.startsWith('user_') || idStr.startsWith('channel_')) {
        // Для пользовательских/канальных рецептов тоже извлекаем числовую часть.
        final numPart = idStr.replaceFirst(RegExp(r'^(user_|channel_)'), '');
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
      previewComments: (json['preview_comments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => PostCommentPreview.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.text.isNotEmpty)
          .toList(),
      repostsCount: json['reposts_count'] as int? ?? 0,
      viewsCount: json['views_count'] as int? ?? 0,
      isPromoted: json['is_promoted'] as bool? ??
          json['isPromoted'] as bool? ??
          false,
      isPaid: json['is_paid'] as bool? ?? false,
      priceStars: json['price_stars'] as int? ?? 0,
      previewMode: json['preview_mode'] as String? ?? 'teaser',
      purchased: json['purchased'] as bool? ?? !(json['is_paid'] as bool? ?? false),
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
      visibility: json['visibility'] as String? ?? 'public',
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
      'preview_comments': previewComments.map((e) => e.toJson()).toList(),
      'reposts_count': repostsCount,
      'views_count': viewsCount,
      'is_promoted': isPromoted,
      'is_pinned': isPinned,
      'is_exclusive': isExclusive,
      'is_paid': isPaid,
      'price_stars': priceStars,
      'preview_mode': previewMode,
      'purchased': purchased,
      'is_liked': isLiked,
      'is_saved': isSaved,
      'is_reposted': isReposted,
      'author': author?.toJson(),
      'reposted_by': repostedBy?.toJson(),
      'channel': channel?.toJson(),
      'visibility': visibility,
    };
  }

  PostModel copyWith({
    String? visibility,
    Map<String, dynamic>? body,
    int? likesCount,
    int? commentsCount,
    List<PostCommentPreview>? previewComments,
    int? repostsCount,
    bool? isLiked,
    bool? isSaved,
    bool? isReposted,
    bool? purchased,
  }) {
    return PostModel(
      id: id,
      type: type,
      title: title,
      description: description,
      status: status,
      createdAt: createdAt,
      publishedAt: publishedAt,
      userId: userId,
      communityId: communityId,
      body: body ?? this.body,
      tags: tags,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      previewComments: previewComments ?? this.previewComments,
      repostsCount: repostsCount ?? this.repostsCount,
      viewsCount: viewsCount,
      isPromoted: isPromoted,
      isPinned: isPinned,
      isExclusive: isExclusive,
      isPaid: isPaid,
      priceStars: priceStars,
      previewMode: previewMode,
      purchased: purchased ?? this.purchased,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      isReposted: isReposted ?? this.isReposted,
      author: author,
      repostedBy: repostedBy,
      channel: channel,
      visibility: visibility ?? this.visibility,
    );
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
      isPromotedFromApi: isPromoted,
      isLiked: isLiked,
      isSaved: isSaved ?? false,
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

/// Не затирает локально закрытый опрос устаревшими данными ленты/кэша.
PostModel applyIncomingPostPreservingLocalPoll(
  PostModel local,
  PostModel incoming,
) {
  final localPoll = local.poll;
  final incomingPoll = incoming.poll;
  if (localPoll == null ||
      incomingPoll == null ||
      !localPoll.isClosed ||
      incomingPoll.isClosed) {
    return incoming;
  }
  final body = Map<String, dynamic>.from(incoming.body ?? {});
  body['poll'] = localPoll.toJson();
  return incoming.copyWith(body: body);
}

class PostAuthorModel {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  /// Комментарий к репосту (если объект пришёл в [reposted_by]).
  final String? comment;

  PostAuthorModel({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.comment,
  });

  factory PostAuthorModel.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_url'] as String?;
    return PostAuthorModel(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: rawAvatar != null && rawAvatar.isNotEmpty
          ? ServerConfig.resolveMediaUrl(rawAvatar)
          : null,
      comment: json['comment'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'avatar_url': avatarUrl,
      if (comment != null && comment!.trim().isNotEmpty) 'comment': comment,
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
    final rawAvatar = json['avatar_url'] as String?;
    final rawCover = json['cover_url'] as String?;
    return ChannelModel(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      avatarUrl: rawAvatar != null && rawAvatar.isNotEmpty
          ? ServerConfig.resolveMediaUrl(rawAvatar)
          : null,
      coverUrl: rawCover != null && rawCover.isNotEmpty
          ? ServerConfig.resolveMediaUrl(rawCover)
          : null,
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

