import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';
import '../models/post_model.dart';
import 'channel_service.dart';

/// Кэш результатов глобального поиска (первая страница, последние запросы).
class GlobalSearchCache {
  GlobalSearchCache._();

  static const _key = 'global_search_cache_v1';
  static const _maxEntries = 15;

  static final Map<String, GlobalSearchCachedResult> _memory = {};

  static String buildKey({
    String? scope,
    required String mainTab,
    required String query,
    String? messageType,
    bool followingOnly = false,
    String? postType,
    String? sortBy,
    String? tags,
    String? dateFrom,
    String? dateTo,
    int? minLikes,
    int? minComments,
    bool recipeSearch = false,
  }) {
    return [
      scope ?? 'main',
      mainTab,
      recipeSearch ? 'recipe' : 'posts',
      followingOnly ? '1' : '0',
      postType ?? '',
      sortBy ?? 'relevance',
      tags ?? '',
      dateFrom ?? '',
      dateTo ?? '',
      minLikes?.toString() ?? '',
      minComments?.toString() ?? '',
      messageType ?? '',
      query.trim().toLowerCase(),
    ].join('|');
  }

  static GlobalSearchCachedResult? peek(String cacheKey) => _memory[cacheKey];

  static Future<void> warmUp() async {
    if (_memory.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final payload = entry.value;
        if (payload is! Map<String, dynamic>) continue;
        _memory[entry.key] = GlobalSearchCachedResult.fromStored(payload);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('GlobalSearchCache.warmUp: $e');
    }
  }

  static Future<void> save(
    String cacheKey,
    GlobalSearchCachedResult result,
  ) async {
    if (!result.hasContent) return;
    _memory[cacheKey] = result;
    while (_memory.length > _maxEntries) {
      _memory.remove(_memory.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, dynamic>{
        for (final e in _memory.entries) e.key: e.value.toStored(),
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (e) {
      if (kDebugMode) debugPrint('GlobalSearchCache.save: $e');
    }
  }
}

class GlobalSearchCachedResult {
  const GlobalSearchCachedResult({
    this.posts = const [],
    this.total = 0,
    this.people = const [],
    this.channels = const [],
  });

  final List<PostModel> posts;
  final int total;
  final List<ChatUserSearchItem> people;
  final List<Channel> channels;

  bool get hasContent =>
      posts.isNotEmpty || people.isNotEmpty || channels.isNotEmpty;

  Map<String, dynamic> toStored() {
    return {
      'posts': posts.map((p) => p.toJson()).toList(),
      'total': total,
      'people': people.map((p) => p.toJson()).toList(),
      'channels': channels.map(_channelToStored).toList(),
    };
  }

  factory GlobalSearchCachedResult.fromStored(Map<String, dynamic> map) {
    final postList = map['posts'] as List<dynamic>? ?? const [];
    final peopleList = map['people'] as List<dynamic>? ?? const [];
    final channelList = map['channels'] as List<dynamic>? ?? const [];
    return GlobalSearchCachedResult(
      posts: postList
          .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: map['total'] as int? ?? 0,
      people: peopleList
          .map((e) => ChatUserSearchItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      channels: channelList
          .map((e) => Channel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

Map<String, dynamic> _channelToStored(Channel channel) {
  return {
    'id': channel.id,
    'name': channel.name,
    'slug': channel.slug,
    if (channel.description != null) 'description': channel.description,
    if (channel.coverUrl != null) 'cover_url': channel.coverUrl,
    if (channel.avatarUrl != null) 'avatar_url': channel.avatarUrl,
    'admin_user_id': channel.adminUserId,
    'is_public': channel.isPublic,
    'has_creator_badge': channel.hasCreatorBadge,
    if (channel.accentColor != null) 'accent_color': channel.accentColor,
    if (channel.category != null) 'category': channel.category,
    'members_count': channel.membersCount,
    'posts_count': channel.postsCount,
    'created_at': channel.createdAt.toUtc().toIso8601String(),
    'auto_publish_reels': channel.autoPublishReels,
    'membership_status': channel.membershipStatus,
    if (channel.pendingJoinRequestsCount != null)
      'pending_join_requests_count': channel.pendingJoinRequestsCount,
    if (channel.lastPostPreview != null)
      'last_post_preview': channel.lastPostPreview,
    if (channel.lastPostAt != null)
      'last_post_at': channel.lastPostAt!.toUtc().toIso8601String(),
    if (channel.seenPostsCount != null)
      'seen_posts_count': channel.seenPostsCount,
  };
}
