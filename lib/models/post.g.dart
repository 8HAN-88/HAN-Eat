// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Post _$PostFromJson(Map<String, dynamic> json) => Post(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.parse(json['published_at'] as String),
      userId: (json['user_id'] as num).toInt(),
      communityId: (json['community_id'] as num?)?.toInt(),
      channelId: (json['channel_id'] as num?)?.toInt(),
      body: json['body'] as Map<String, dynamic>?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      likesCount: (json['likes_count'] as num).toInt(),
      commentsCount: (json['comments_count'] as num).toInt(),
      repostsCount: (json['reposts_count'] as num?)?.toInt(),
      isLiked: json['is_liked'] as bool,
      isSaved: json['is_saved'] as bool? ?? false,
      isPromotedFromApi: json['is_promoted'] as bool? ?? false,
      author: json['author'] == null
          ? null
          : PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PostToJson(Post instance) => <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'title': instance.title,
      'description': instance.description,
      'status': instance.status,
      'created_at': instance.createdAt.toIso8601String(),
      'published_at': instance.publishedAt?.toIso8601String(),
      'user_id': instance.userId,
      'community_id': instance.communityId,
      'channel_id': instance.channelId,
      'body': instance.body,
      'tags': instance.tags,
      'likes_count': instance.likesCount,
      'comments_count': instance.commentsCount,
      'reposts_count': instance.repostsCount,
      'is_liked': instance.isLiked,
      'is_saved': instance.isSaved,
      'is_promoted': instance.isPromotedFromApi,
      'author': instance.author,
    };

PostAuthor _$PostAuthorFromJson(Map<String, dynamic> json) => PostAuthor(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );

Map<String, dynamic> _$PostAuthorToJson(PostAuthor instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'username': instance.username,
      'avatarUrl': instance.avatarUrl,
    };
