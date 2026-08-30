// Сервис для работы с каналами
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

/// Канал удалён или не существует (ответ API 404).
class ChannelNotFoundException implements Exception {
  @override
  String toString() => 'Канал не найден или удалён';
}

/// Аватар/обложка с API часто с localhost:5000 — приводим к тому же хосту/порту, что и клиент.
String? _resolveChannelMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  return ServerConfig.resolveMediaUrl(url);
}

class ChannelService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Создать канал
  static Future<Channel> createChannel({
    required String name,
    required String slug,
    String? description,
    String? coverUrl,
    String? avatarUrl,
    bool isPublic = true,
    String? category,
    bool isPaid = false,
    int monthlyPriceStars = 0,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'slug': slug,
        if (description != null) 'description': description,
        if (coverUrl != null) 'cover_url': coverUrl,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'is_public': isPublic,
        if (category != null && category.isNotEmpty) 'category': category,
        'is_paid': isPaid,
        'monthly_price_stars': monthlyPriceStars,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Channel.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create channel');
    }
  }

  /// Обновить канал
  static Future<Channel> updateChannel({
    required int channelId,
    required String name,
    required String slug,
    String? description,
    String? coverUrl,
    String? avatarUrl,
    bool? isPublic,
    String? category,
    List<String>? tags,
    String? rules,
    bool? autoPublishToFeed,
    bool? autoPublishReels,
    bool? allowComments,
    bool? allowLikes,
    bool? allowReposts,
    Map<String, Map<String, bool>>? rolePermissions,
    String? accentColor,
  }) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId');
    final bodyMap = <String, dynamic>{
      'name': name,
      'slug': slug,
      if (description != null) 'description': description,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (isPublic != null) 'is_public': isPublic,
      if (category != null && category.isNotEmpty) 'category': category,
      if (tags != null) 'tags': tags,
      if (rules != null) 'rules': rules,
      if (autoPublishToFeed != null) 'auto_publish_to_feed': autoPublishToFeed,
      if (autoPublishReels != null) 'auto_publish_reels': autoPublishReels,
      if (allowComments != null) 'allow_comments': allowComments,
      if (allowLikes != null) 'allow_likes': allowLikes,
      if (allowReposts != null) 'allow_reposts': allowReposts,
      if (rolePermissions != null) 'role_permissions': rolePermissions,
      if (accentColor != null) 'accent_color': accentColor,
    };
    final body = jsonEncode(bodyMap);

    Future<http.Response> doPut(String t) async {
      return http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: body,
      );
    }

    var response = await doPut(token);

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await doPut(token);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Channel.fromJson(data);
    } else {
      final detail = () {
        try {
          final m = jsonDecode(response.body);
          if (m is Map && m['detail'] != null) return m['detail'].toString();
        } catch (_) {}
        return response.body.isNotEmpty
            ? response.body
            : 'Failed to update channel (${response.statusCode})';
      }();
      throw Exception(detail);
    }
  }

  /// Получить информацию о канале
  static Future<ChannelDetail> getChannel(int channelId) async {
    final token = await AuthService.getAccessTokenForApi();

    final uri = Uri.parse('$baseUrl/channels/$channelId');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelDetail.fromJson(data);
    }
    if (response.statusCode == 404) {
      throw ChannelNotFoundException();
    }
    throw Exception('Failed to load channel (${response.statusCode})');
  }

  /// Вкл/выкл уведомления о постах канала (только для подписчика, сервер).
  static Future<bool> setChannelNotificationsEnabled({
    required int channelId,
    required bool enabled,
  }) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/notifications');
    var response = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'enabled': enabled}),
    );

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'enabled': enabled}),
      );
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['enabled'] as bool? ?? enabled;
    }
    String msg = 'Ошибка сервера';
    try {
      final err = jsonDecode(response.body) as Map<String, dynamic>?;
      msg = err?['detail']?.toString() ?? msg;
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  /// Отметить посты канала просмотренными в inbox.
  static Future<int> markChannelInboxRead(int channelId) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/inbox-read');
    var response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['seen_posts_count'] as int? ?? 0;
    }
    String msg = 'Ошибка сервера';
    try {
      final err = jsonDecode(response.body) as Map<String, dynamic>?;
      msg = err?['detail']?.toString() ?? msg;
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  /// Получить список каналов
  static Future<ChannelsListResponse> listChannels({
    int limit = 20,
    int offset = 0,
    String? search,
    bool? subscribed,
    bool? mine,
    bool? recommended,
    bool? catalog,
    String? category,
    String? sort, // popular, new, members, activity, posts
    String? mode, // recommendations | catalog
    int? minSubscribers,
    int? maxSubscribers,
    int? minPosts,
    bool withLastPost = false,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (subscribed == true) {
      queryParams['subscribed'] = 'true';
    }
    if (mine == true) {
      queryParams['mine'] = 'true';
    }
    if (recommended == true) {
      queryParams['recommended'] = 'true';
    }
    if (catalog == true) {
      queryParams['catalog'] = 'true';
    }
    if (mode != null && mode.isNotEmpty) {
      queryParams['mode'] = mode;
    }
    if (category != null && category.isNotEmpty) {
      queryParams['category'] = category;
    }
    if (sort != null && sort.isNotEmpty) {
      queryParams['sort'] = sort;
    }
    if (minSubscribers != null) {
      queryParams['min_subscribers'] = minSubscribers.toString();
    }
    if (maxSubscribers != null) {
      queryParams['max_subscribers'] = maxSubscribers.toString();
    }
    if (minPosts != null) {
      queryParams['min_posts'] = minPosts.toString();
    }
    if (withLastPost) {
      queryParams['with_last_post'] = 'true';
    }

    final uri =
        Uri.parse('$baseUrl/channels').replace(queryParameters: queryParams);

    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await AuthService.getAccessTokenForApi();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelsListResponse.fromJson(data);
    }
    String detail = 'Не удалось загрузить каналы';
    try {
      final err = jsonDecode(response.body) as Map<String, dynamic>?;
      detail = err?['detail']?.toString() ?? detail;
    } catch (_) {}
    throw Exception('$detail (${response.statusCode})');
  }

  /// Сумма непрочитанных постов в inbox каналов (один запрос).
  static Future<int> inboxUnreadCount() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) return 0;

    final uri = Uri.parse('$baseUrl/channels/inbox-unread-count');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['count'] as int? ?? 0;
    }
    throw Exception('Failed to load channel inbox unread count');
  }

  static Future<List<ChannelInboxPrefs>> listInboxPrefs() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) return [];

    final uri = Uri.parse('$baseUrl/channels/inbox-prefs');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(ChannelInboxPrefs.fromJson)
          .toList();
    }
    throw Exception('Failed to load channel inbox prefs');
  }

  static Future<ChannelInboxPrefs> patchInboxPrefs({
    required int channelId,
    bool? isFavorite,
    bool? inboxArchived,
    bool? showInFeed,
    bool? notificationsEnabled,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final body = <String, dynamic>{};
    if (isFavorite != null) body['is_favorite'] = isFavorite;
    if (inboxArchived != null) body['inbox_archived'] = inboxArchived;
    if (showInFeed != null) body['show_in_feed'] = showInFeed;
    if (notificationsEnabled != null) {
      body['notifications_enabled'] = notificationsEnabled;
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/inbox-prefs');
    final response = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelInboxPrefs.fromJson(data);
    }
    throw Exception('Failed to update channel inbox prefs');
  }

  /// Присоединиться к каналу
  static Future<JoinChannelResponse> joinChannel(int channelId) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/join');
    var response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    // Если получили 401, пытаемся обновить токен и повторить запрос
    if (response.statusCode == 401) {
      try {
        token = await AuthService.refreshToken();
        response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      } catch (e) {
        throw Exception('Authentication failed. Please log in again.');
      }
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return JoinChannelResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(
          error?['detail'] ?? 'Failed to join channel: ${response.statusCode}');
    }
  }

  /// Заявки на вступление (для модераторов канала).
  static Future<ChannelJoinRequestsResponse> getChannelJoinRequests(
    int channelId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/join-requests')
        .replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelJoinRequestsResponse.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>?;
    throw Exception(
      error?['detail'] ??
          'Failed to load join requests: ${response.statusCode}',
    );
  }

  static Future<void> approveChannelJoinRequest(
    int channelId,
    int userId,
  ) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse(
      '$baseUrl/channels/$channelId/join-requests/$userId/approve',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(
        error?['detail'] ??
            'Failed to approve join request: ${response.statusCode}',
      );
    }
  }

  static Future<void> rejectChannelJoinRequest(
    int channelId,
    int userId,
  ) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse(
      '$baseUrl/channels/$channelId/join-requests/$userId/reject',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204) {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(
        error?['detail'] ??
            'Failed to reject join request: ${response.statusCode}',
      );
    }
  }

  /// Покинуть канал
  static Future<JoinChannelResponse> leaveChannel(int channelId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/join');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return JoinChannelResponse.fromJson(data);
    } else {
      throw Exception('Failed to leave channel');
    }
  }

  /// Получить посты канала
  static Future<ChannelPostsResponse> getChannelPosts({
    required int channelId,
    int limit = 20,
    int offset = 0,
    String? postType, // Фильтр по типу: text, photo, recipe, reel
    String? search, // Поисковый запрос
    bool fresh = false,
  }) async {
    var token = await AuthService.getAccessTokenForApi();

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (fresh) {
      queryParams['fresh'] = 'true';
    }
    if (postType != null && postType.isNotEmpty) {
      queryParams['post_type'] = postType;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/posts').replace(
      queryParameters: queryParams,
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    var response = await http.get(uri, headers: headers);

    // Если получили 401, пытаемся обновить токен и повторить запрос
    if (response.statusCode == 401 && token != null) {
      try {
        token = await AuthService.refreshToken();
        headers['Authorization'] = 'Bearer $token';
        response = await http.get(uri, headers: headers);
      } catch (e) {
        debugPrint('ChannelService: refresh after 401 failed: $e');
        rethrow;
      }
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelPostsResponse.fromJson(data);
    } else {
      throw Exception('Failed to load channel posts');
    }
  }

  /// Получить список подписчиков канала.
  static Future<Map<String, dynamic>> getChannelMembers({
    required int channelId,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessTokenForApi();

    final uri = Uri.parse('$baseUrl/channels/$channelId/members').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Не удалось загрузить подписчиков канала');
    }
  }

  /// Обновить пост в канале
  static Future<Map<String, dynamic>> updateChannelPost({
    required int channelId,
    required int postId,
    String? title,
    String? description,
    List<Map<String, dynamic>>? media,
    List<String>? tags,
    String? visibility,
    String? linkUrl,
    String? linkPreview,
    String? pollQuestion,
    List<String>? pollOptions,
    String? originCountryCode,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/posts/$postId');

    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (visibility != null) body['visibility'] = visibility;
    if (description != null) body['description'] = description;
    if (media != null) body['media'] = media;
    if (tags != null) body['tags'] = tags;
    if (linkUrl != null) {
      body['link'] = {
        'url': linkUrl,
        if (linkPreview != null && linkPreview.isNotEmpty)
          'preview': linkPreview,
      };
    }
    if (pollQuestion != null && pollOptions != null) {
      body['poll'] = {
        'question': pollQuestion,
        'options': pollOptions,
      };
    }
    if (originCountryCode != null) {
      body['origin_country_code'] = originCountryCode;
    }

    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось обновить пост',
    );
  }

  /// Удалить пост из канала
  static Future<void> deleteChannelPost({
    required int channelId,
    required int postId,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/posts/$postId');

    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw apiExceptionFromResponse(
          response.statusCode,
          error,
          fallback: 'Не удалось удалить пост',
        );
      } catch (e) {
        if (e is ApiClientException) rethrow;
        throw ApiClientException(
          statusCode: response.statusCode,
          message: 'Не удалось удалить пост',
        );
      }
    }
  }

  /// Создать обычный пост в канале (текст, изображения, видео)
  static Future<Map<String, dynamic>> createChannelPost({
    required int channelId,
    required String type, // 'text', 'photo', 'reel'
    String? title,
    String? description,
    List<Map<String, dynamic>>? media, // [{type: 'image'|'video', url: String}]
    List<String>? tags,
    bool? publishToReels,
    DateTime? scheduledPublishAt,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/post');

    final body = <String, dynamic>{
      'type': type,
      if (title != null && title.isNotEmpty) 'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (media != null && media.isNotEmpty) 'media': media,
      if (publishToReels != null) 'publish_to_reels': publishToReels,
      if (scheduledPublishAt != null)
        'scheduled_publish_at': scheduledPublishAt.toUtc().toIso8601String(),
    };

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось создать пост в канале',
    );
  }

  /// Обновить роль подписчика канала.
  static Future<void> updateChannelMemberRole({
    required int channelId,
    required int userId,
    required String role, // 'admin', 'moderator', 'member'
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/members/$userId/role');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'role': role}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to update member role');
    }
  }

  /// Удалить подписчика из канала.
  static Future<CreatorStats> getCreatorStats() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/stats');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return CreatorStats.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось загрузить статистику Creator',
    );
  }

  static Future<List<PromotedPostSummary>> getPromotedPosts() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/promoted');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['posts'] as List<dynamic>? ?? [];
      return list
          .map((e) => PromotedPostSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось загрузить продвигаемые посты',
    );
  }

  static Future<List<ScheduledPostSummary>> getScheduledPosts() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/scheduled');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['posts'] as List<dynamic>? ?? [];
      return list
          .map((e) => ScheduledPostSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось загрузить запланированные посты',
    );
  }

  static Future<void> rescheduleScheduledPost({
    required int postId,
    required DateTime scheduledPublishAt,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/schedule');
    final response = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'scheduled_publish_at': scheduledPublishAt.toUtc().toIso8601String(),
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromResponse(
        response.statusCode,
        error,
        fallback: 'Не удалось изменить время публикации',
      );
    }
  }

  static Future<void> cancelScheduledPost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/schedule');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromResponse(
        response.statusCode,
        error,
        fallback: 'Не удалось отменить публикацию',
      );
    }
  }

  static Future<Map<String, dynamic>> unpromotePost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/promote');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось снять продвижение',
    );
  }

  /// Продвижение поста в ленте (Creator / Pro).
  static Future<Map<String, dynamic>> pinPost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/pin');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось закрепить пост',
    );
  }

  static Future<Map<String, dynamic>> unpinPost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/pin');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось открепить пост',
    );
  }

  static Future<Map<String, dynamic>> promotePost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/creator/posts/$postId/promote');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось продвинуть пост',
    );
  }

  static Future<void> removeChannelMember({
    required int channelId,
    required int userId,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/members/$userId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to remove member');
    }
  }

  /// Удалить канал (только владелец)
  static Future<void> deleteChannel(int channelId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to delete channel');
    }
  }
}

class Channel {
  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? coverUrl;
  final String? avatarUrl;
  final int adminUserId;
  final bool isPublic;
  final bool isPaid;
  final int monthlyPriceStars;
  final bool paidAccess;
  final bool hasCreatorBadge;
  final String? accentColor;
  final String? category;
  final int membersCount;
  final int postsCount;
  final DateTime createdAt;
  final bool autoPublishReels;
  final String membershipStatus;
  final int? pendingJoinRequestsCount;
  final String? lastPostPreview;
  final DateTime? lastPostAt;
  final int? seenPostsCount;

  bool get isPending => membershipStatus == 'pending';
  bool get isActiveMember => membershipStatus == 'active';
  bool get canLoadPostsPreview => isPublic || isActiveMember;

  int get inboxUnreadPosts {
    final seen = seenPostsCount ?? 0;
    final delta = postsCount - seen;
    return delta > 0 ? delta : 0;
  }

  Channel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.coverUrl,
    this.avatarUrl,
    required this.adminUserId,
    required this.isPublic,
    this.isPaid = false,
    this.monthlyPriceStars = 0,
    this.paidAccess = true,
    this.hasCreatorBadge = false,
    this.accentColor,
    this.category,
    required this.membersCount,
    required this.postsCount,
    required this.createdAt,
    required this.autoPublishReels,
    this.membershipStatus = 'none',
    this.pendingJoinRequestsCount,
    this.lastPostPreview,
    this.lastPostAt,
    this.seenPostsCount,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      coverUrl: _resolveChannelMediaUrl(json['cover_url'] as String?),
      avatarUrl: _resolveChannelMediaUrl(json['avatar_url'] as String?),
      adminUserId: json['admin_user_id'] as int,
      isPublic: json['is_public'] as bool,
      isPaid: json['is_paid'] as bool? ?? false,
      monthlyPriceStars: json['monthly_price_stars'] as int? ?? 0,
      paidAccess: json['paid_access'] as bool? ?? true,
      hasCreatorBadge: json['has_creator_badge'] as bool? ?? false,
      accentColor: json['accent_color'] as String?,
      category: json['category'] as String?,
      membersCount: json['members_count'] as int,
      postsCount: json['posts_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      autoPublishReels: json['auto_publish_reels'] as bool? ?? true,
      membershipStatus: json['membership_status'] as String? ?? 'none',
      pendingJoinRequestsCount: json['pending_join_requests_count'] as int?,
      lastPostPreview: json['last_post_preview'] as String?,
      lastPostAt: json['last_post_at'] != null
          ? DateTime.tryParse(json['last_post_at'] as String)?.toLocal()
          : null,
      seenPostsCount: json['seen_posts_count'] as int?,
    );
  }
}

class ChannelDetail extends Channel {
  final Map<String, dynamic>? adminUser;
  final bool isMember;
  final bool isAdmin;
  final bool isOwner;
  final bool isModerator;
  final List<String>? tags;
  final String? rules;
  final bool? autoPublishToFeed;
  final bool? allowComments;
  final bool? allowLikes;
  final bool? allowReposts;
  final Map<String, Map<String, bool>> rolePermissions;

  /// С сервера: включены ли уведомления для текущего пользователя (только если [isMember]).
  final bool? channelNotificationsEnabled;
  final bool canViewPosts;

  ChannelDetail({
    required super.id,
    required super.name,
    required super.slug,
    super.description,
    super.coverUrl,
    super.avatarUrl,
    required super.adminUserId,
    required super.isPublic,
    super.isPaid,
    super.monthlyPriceStars,
    super.paidAccess,
    super.hasCreatorBadge,
    super.accentColor,
    super.category,
    required super.membersCount,
    required super.postsCount,
    required super.createdAt,
    required super.autoPublishReels,
    super.membershipStatus = 'none',
    super.pendingJoinRequestsCount,
    this.adminUser,
    required this.isMember,
    required this.isAdmin,
    required this.isOwner,
    required this.isModerator,
    this.tags,
    this.rules,
    this.autoPublishToFeed,
    this.allowComments,
    this.allowLikes,
    this.allowReposts,
    Map<String, Map<String, bool>>? rolePermissions,
    this.channelNotificationsEnabled,
    this.canViewPosts = true,
  }) : rolePermissions = rolePermissions ?? defaultChannelRolePermissions();

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    final rolePermissions = _rolePermissionsFromJson(json['role_permissions']);
    return ChannelDetail(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      coverUrl: _resolveChannelMediaUrl(json['cover_url'] as String?),
      avatarUrl: _resolveChannelMediaUrl(json['avatar_url'] as String?),
      adminUserId: json['admin_user_id'] as int,
      isPublic: json['is_public'] as bool,
      isPaid: json['is_paid'] as bool? ?? false,
      monthlyPriceStars: json['monthly_price_stars'] as int? ?? 0,
      paidAccess: json['paid_access'] as bool? ?? true,
      hasCreatorBadge: json['has_creator_badge'] as bool? ?? false,
      accentColor: json['accent_color'] as String?,
      category: json['category'] as String?,
      membersCount: json['members_count'] as int,
      postsCount: json['posts_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      autoPublishReels: json['auto_publish_reels'] as bool? ?? true,
      adminUser: json['admin_user'] as Map<String, dynamic>?,
      isMember: json['is_member'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      isOwner: json['is_owner'] as bool? ?? false,
      isModerator: json['is_moderator'] as bool? ?? false,
      tags:
          json['tags'] != null ? List<String>.from(json['tags'] as List) : null,
      rules: json['rules'] as String?,
      autoPublishToFeed: json['auto_publish_to_feed'] as bool?,
      allowComments: json['allow_comments'] as bool?,
      allowLikes: json['allow_likes'] as bool?,
      allowReposts: json['allow_reposts'] as bool?,
      rolePermissions: rolePermissions,
      channelNotificationsEnabled:
          json['channel_notifications_enabled'] as bool?,
      membershipStatus: json['membership_status'] as String? ?? 'none',
      canViewPosts: json['can_view_posts'] as bool? ?? true,
      pendingJoinRequestsCount: json['pending_join_requests_count'] as int?,
    );
  }

  bool hasPermission(String permission) {
    if (isOwner) return true;
    final role = isAdmin
        ? 'admin'
        : isModerator
            ? 'moderator'
            : null;
    if (role == null) return false;
    return rolePermissions[role]?[permission] ?? false;
  }

  bool get canManageChannelSettings => hasPermission('manage_channel_settings');
  bool get canManageSubscribers => hasPermission('manage_subscribers');
  bool get canManageJoinRequests => hasPermission('manage_join_requests');
  bool get canCreatePosts => hasPermission('create_posts');
  bool get canEditAnyPost => hasPermission('edit_any_post');
  bool get canDeleteAnyPost => hasPermission('delete_any_post');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'cover_url': coverUrl,
      'avatar_url': avatarUrl,
      'admin_user_id': adminUserId,
      'is_public': isPublic,
      'is_paid': isPaid,
      'monthly_price_stars': monthlyPriceStars,
      'paid_access': paidAccess,
      'category': category,
      'members_count': membersCount,
      'posts_count': postsCount,
      'created_at': createdAt.toIso8601String(),
      'auto_publish_reels': autoPublishReels,
      'admin_user': adminUser,
      'is_member': isMember,
      'is_admin': isAdmin,
      'is_owner': isOwner,
      'is_moderator': isModerator,
      'tags': tags,
      'rules': rules,
      'auto_publish_to_feed': autoPublishToFeed,
      'allow_comments': allowComments,
      'allow_likes': allowLikes,
      'allow_reposts': allowReposts,
      'role_permissions': rolePermissions,
      'channel_notifications_enabled': channelNotificationsEnabled,
      'membership_status': membershipStatus,
      'can_view_posts': canViewPosts,
      'pending_join_requests_count': pendingJoinRequestsCount,
    };
  }
}

const channelPermissionKeys = <String>[
  'manage_channel_settings',
  'manage_subscribers',
  'manage_join_requests',
  'create_posts',
  'edit_any_post',
  'delete_any_post',
];

Map<String, Map<String, bool>> defaultChannelRolePermissions() {
  return {
    'admin': {
      'manage_channel_settings': true,
      'manage_subscribers': true,
      'manage_join_requests': true,
      'create_posts': true,
      'edit_any_post': true,
      'delete_any_post': true,
    },
    'moderator': {
      'manage_channel_settings': false,
      'manage_subscribers': false,
      'manage_join_requests': true,
      'create_posts': true,
      'edit_any_post': true,
      'delete_any_post': true,
    },
  };
}

Map<String, Map<String, bool>> _rolePermissionsFromJson(dynamic raw) {
  final normalized = defaultChannelRolePermissions();
  if (raw is! Map) return normalized;
  for (final role in const ['admin', 'moderator']) {
    final roleRaw = raw[role];
    if (roleRaw is! Map) continue;
    for (final key in channelPermissionKeys) {
      final value = roleRaw[key];
      if (value is bool) {
        normalized[role]![key] = value;
      }
    }
  }
  return normalized;
}

class ChannelsListResponse {
  final List<Channel> items;
  final int total;

  ChannelsListResponse({
    required this.items,
    required this.total,
  });

  factory ChannelsListResponse.fromJson(Map<String, dynamic> json) {
    return ChannelsListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Channel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

class CreatorStats {
  final bool hasCreator;
  final bool canPromote;
  final bool canSchedule;
  final bool canPin;
  final bool canAnalytics;
  final bool canTools;
  final int promotedCount;
  final int promotedLimit;
  final int scheduledCount;

  CreatorStats({
    required this.hasCreator,
    this.canPromote = false,
    this.canSchedule = false,
    this.canPin = false,
    this.canAnalytics = false,
    this.canTools = false,
    required this.promotedCount,
    required this.promotedLimit,
    required this.scheduledCount,
  });

  factory CreatorStats.fromJson(Map<String, dynamic> json) {
    return CreatorStats(
      hasCreator: json['has_creator'] as bool? ?? false,
      canPromote: json['can_promote'] as bool? ?? false,
      canSchedule: json['can_schedule'] as bool? ?? false,
      canPin: json['can_pin'] as bool? ?? false,
      canAnalytics: json['can_analytics'] as bool? ?? false,
      canTools: json['can_tools'] as bool? ?? false,
      promotedCount: json['promoted_count'] as int? ?? 0,
      promotedLimit: json['promoted_limit'] as int? ?? 5,
      scheduledCount: json['scheduled_count'] as int? ?? 0,
    );
  }
}

class PromotedPostSummary {
  final int id;
  final String? title;
  final String type;
  final int? channelId;
  final DateTime? publishedAt;

  PromotedPostSummary({
    required this.id,
    this.title,
    required this.type,
    this.channelId,
    this.publishedAt,
  });

  factory PromotedPostSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) =>
        s != null ? DateTime.parse(s).toLocal() : null;
    return PromotedPostSummary(
      id: json['id'] as int,
      title: json['title'] as String?,
      type: json['type'] as String? ?? 'post',
      channelId: json['channel_id'] as int?,
      publishedAt: parse(json['published_at'] as String?),
    );
  }
}

class ScheduledPostSummary {
  final int id;
  final String? title;
  final String type;
  final int? channelId;
  final DateTime? scheduledPublishAt;

  ScheduledPostSummary({
    required this.id,
    this.title,
    required this.type,
    this.channelId,
    this.scheduledPublishAt,
  });

  factory ScheduledPostSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['scheduled_publish_at'] as String?;
    return ScheduledPostSummary(
      id: json['id'] as int,
      title: json['title'] as String?,
      type: json['type'] as String? ?? 'text',
      channelId: json['channel_id'] as int?,
      scheduledPublishAt: raw != null ? DateTime.parse(raw).toLocal() : null,
    );
  }
}

class JoinChannelResponse {
  final bool joined;
  final bool pending;
  final int membersCount;
  final String membershipStatus;

  JoinChannelResponse({
    required this.joined,
    this.pending = false,
    required this.membersCount,
    this.membershipStatus = 'none',
  });

  factory JoinChannelResponse.fromJson(Map<String, dynamic> json) {
    return JoinChannelResponse(
      joined: json['joined'] as bool? ?? false,
      pending: json['pending'] as bool? ?? false,
      membersCount: json['members_count'] as int,
      membershipStatus: json['membership_status'] as String? ?? 'none',
    );
  }
}

class ChannelJoinRequest {
  final int id;
  final int userId;
  final int channelId;
  final DateTime joinedAt;
  final Map<String, dynamic>? user;

  ChannelJoinRequest({
    required this.id,
    required this.userId,
    required this.channelId,
    required this.joinedAt,
    this.user,
  });

  factory ChannelJoinRequest.fromJson(Map<String, dynamic> json) {
    return ChannelJoinRequest(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      channelId: json['channel_id'] as int,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      user: json['user'] as Map<String, dynamic>?,
    );
  }
}

class ChannelJoinRequestsResponse {
  final List<ChannelJoinRequest> items;
  final int total;

  ChannelJoinRequestsResponse({
    required this.items,
    required this.total,
  });

  factory ChannelJoinRequestsResponse.fromJson(Map<String, dynamic> json) {
    return ChannelJoinRequestsResponse(
      items: (json['items'] as List<dynamic>)
          .map(
            (e) => ChannelJoinRequest.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}

class ChannelPostsResponse {
  final List<Map<String, dynamic>> posts;
  final int total;

  ChannelPostsResponse({
    required this.posts,
    required this.total,
  });

  factory ChannelPostsResponse.fromJson(Map<String, dynamic> json) {
    return ChannelPostsResponse(
      posts: (json['posts'] as List<dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .toList(),
      total: json['total'] as int,
    );
  }
}

class ChannelInboxPrefs {
  const ChannelInboxPrefs({
    required this.channelId,
    this.isFavorite = false,
    this.inboxArchived = false,
    this.showInFeed = true,
    this.notificationsEnabled = true,
  });

  final int channelId;
  final bool isFavorite;
  final bool inboxArchived;
  final bool showInFeed;
  final bool notificationsEnabled;

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'is_favorite': isFavorite,
        'inbox_archived': inboxArchived,
        'show_in_feed': showInFeed,
        'notifications_enabled': notificationsEnabled,
      };

  factory ChannelInboxPrefs.fromJson(Map<String, dynamic> json) {
    return ChannelInboxPrefs(
      channelId: json['channel_id'] as int? ?? 0,
      isFavorite: json['is_favorite'] as bool? ?? false,
      inboxArchived: json['inbox_archived'] as bool? ?? false,
      showInFeed: json['show_in_feed'] as bool? ?? true,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
    );
  }
}
