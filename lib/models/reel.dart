import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель рилса (короткого видео)
class Reel {
  final String id;
  final String communityId;
  final String authorId;
  final String urlOriginal; // Оригинальное видео
  final String urlTranscoded; // Транскодированное видео
  final String? description;
  final List<String> tags;
  final DateTime createdAt;
  final int views;
  final int likes;
  final int comments;
  final int shares;
  final bool isDeleted;

  Reel({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.urlOriginal,
    required this.urlTranscoded,
    this.description,
    this.tags = const [],
    required this.createdAt,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.isDeleted = false,
  });

  factory Reel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Reel(
      id: doc.id,
      communityId: data['communityId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      urlOriginal: data['urlOriginal'] as String? ?? '',
      urlTranscoded: data['urlTranscoded'] as String? ?? '',
      description: data['description'] as String?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      views: data['views'] as int? ?? 0,
      likes: data['likes'] as int? ?? 0,
      comments: data['comments'] as int? ?? 0,
      shares: data['shares'] as int? ?? 0,
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'communityId': communityId,
      'authorId': authorId,
      'urlOriginal': urlOriginal,
      'urlTranscoded': urlTranscoded,
      if (description != null) 'description': description,
      'tags': tags,
      'createdAt': Timestamp.fromDate(createdAt),
      'views': views,
      'likes': likes,
      'comments': comments,
      'shares': shares,
      'isDeleted': isDeleted,
    };
  }

  Reel copyWith({
    String? id,
    String? communityId,
    String? authorId,
    String? urlOriginal,
    String? urlTranscoded,
    String? description,
    List<String>? tags,
    DateTime? createdAt,
    int? views,
    int? likes,
    int? comments,
    int? shares,
    bool? isDeleted,
  }) {
    return Reel(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      authorId: authorId ?? this.authorId,
      urlOriginal: urlOriginal ?? this.urlOriginal,
      urlTranscoded: urlTranscoded ?? this.urlTranscoded,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      views: views ?? this.views,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

