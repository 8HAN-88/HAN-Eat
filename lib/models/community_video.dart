class CommunityVideo {
  CommunityVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.videoUrl,
    required this.likes,
    this.commentsCount = 0,
    required this.tags,
    required this.createdAt,
    required this.status,
    this.thumbnail,
    this.avatar,
  });

  final int id;
  final String title;
  final String author;
  final String? avatar;
  final String description;
  final String videoUrl;
  final String? thumbnail;
  final int likes;
  final int commentsCount;
  final List<String> tags;
  final DateTime createdAt;
  final String status;

  bool get isPublished => status == 'published';
  bool get isPending => status == 'pending';

  factory CommunityVideo.fromJson(Map<String, dynamic> json) {
    final tags = (json['tags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    return CommunityVideo(
      id: json['id'] as int? ?? 0,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      description: json['description']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString(),
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int? ?? 0) * 1000,
        isUtc: false,
      ),
      status: json['status']?.toString() ?? 'published',
    );
  }

  CommunityVideo copyWith({
    int? likes,
    int? commentsCount,
    String? status,
  }) {
    return CommunityVideo(
      id: id,
      title: title,
      author: author,
      avatar: avatar,
      description: description,
      videoUrl: videoUrl,
      thumbnail: thumbnail,
      likes: likes ?? this.likes,
      commentsCount: commentsCount ?? this.commentsCount,
      tags: tags,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}

