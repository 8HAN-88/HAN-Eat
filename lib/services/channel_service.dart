// Сервис для работы с каналами
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ChannelService {
  static const String baseUrl = 'http://localhost:5000/api/v1';

  /// Создать канал
  static Future<Channel> createChannel({
    required String name,
    required String slug,
    String? description,
    String? coverUrl,
    String? avatarUrl,
    bool isPublic = true,
    String? category,
  }) async {
    final token = await AuthService.getAccessToken();
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
    bool? autoPublishToMenu,
    bool? autoPublishReels,
    bool? allowComments,
    bool? allowLikes,
    bool? allowReposts,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId');
    final response = await http.put(
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
        if (tags != null) 'tags': tags,
        if (rules != null) 'rules': rules,
        if (autoPublishToFeed != null)
          'auto_publish_to_feed': autoPublishToFeed,
        if (autoPublishToMenu != null)
          'auto_publish_to_menu': autoPublishToMenu,
        if (autoPublishReels != null) 'auto_publish_reels': autoPublishReels,
        if (allowComments != null) 'allow_comments': allowComments,
        if (allowLikes != null) 'allow_likes': allowLikes,
        if (allowReposts != null) 'allow_reposts': allowReposts,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Channel.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to update channel');
    }
  }

  /// Получить информацию о канале
  static Future<ChannelDetail> getChannel(int channelId) async {
    final token = await AuthService.getAccessToken();

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
    } else {
      throw Exception('Failed to load channel');
    }
  }

  /// Получить список каналов
  static Future<ChannelsListResponse> listChannels({
    int limit = 20,
    int offset = 0,
    String? search,
    bool? subscribed,
    bool? recommended,
    bool? catalog,
    String? category,
    String? sort, // popular, new, members, activity, posts
    String? mode, // recommendations | catalog
    int? minSubscribers,
    int? maxSubscribers,
    bool? hasRecipes,
    int? minPosts,
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
    if (hasRecipes != null) {
      queryParams['has_recipes'] = hasRecipes.toString();
    }
    if (minPosts != null) {
      queryParams['min_posts'] = minPosts.toString();
    }

    final uri =
        Uri.parse('$baseUrl/channels').replace(queryParameters: queryParams);

    // Для subscribed нужен токен
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (subscribed == true) {
      final token = await AuthService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelsListResponse.fromJson(data);
    } else {
      throw Exception('Failed to load channels');
    }
  }

  /// Присоединиться к каналу
  static Future<JoinChannelResponse> joinChannel(int channelId) async {
    var token = await AuthService.getAccessToken();
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

  /// Покинуть канал
  static Future<JoinChannelResponse> leaveChannel(int channelId) async {
    final token = await AuthService.getAccessToken();
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
  }) async {
    var token = await AuthService.getAccessToken();

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
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
        // Если не удалось обновить токен, продолжаем без авторизации
        headers.remove('Authorization');
        response = await http.get(uri, headers: headers);
      }
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChannelPostsResponse.fromJson(data);
    } else {
      throw Exception('Failed to load channel posts');
    }
  }

  /// Получить список участников канала
  static Future<Map<String, dynamic>> getChannelMembers({
    required int channelId,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessToken();

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
      throw Exception('Failed to load channel members');
    }
  }

  /// Создать рецепт в канале
  static Future<Map<String, dynamic>> createChannelRecipe({
    required int channelId,
    required String title,
    String? description,
    required List<String> ingredients,
    required List<Map<String, dynamic>>
        steps, // [{number: int, text: String, image_url?: String}]
    List<Map<String, dynamic>>? media, // [{type: 'image'|'video', url: String}]
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
    List<String>? tags,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/recipe');

    final body = <String, dynamic>{
      'type': 'recipe',
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'ingredients': ingredients,
      'steps': steps,
      if (prepTimeMin != null) 'prep_time_min': prepTimeMin,
      if (cookTimeMin != null) 'cook_time_min': cookTimeMin,
      if (servings != null) 'servings': servings,
      if (calories != null) 'calories': calories,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (media != null && media.isNotEmpty) 'media': media,
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
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create recipe');
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
    List<String>? ingredients,
    List<Map<String, dynamic>>? steps,
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/posts/$postId');

    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (media != null) body['media'] = media;
    if (tags != null) body['tags'] = tags;
    if (ingredients != null) body['ingredients'] = ingredients;
    if (steps != null) body['steps'] = steps;
    if (prepTimeMin != null) body['prep_time_min'] = prepTimeMin;
    if (cookTimeMin != null) body['cook_time_min'] = cookTimeMin;
    if (servings != null) body['servings'] = servings;
    if (calories != null) body['calories'] = calories;

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
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to update post');
    }
  }

  /// Удалить пост из канала
  static Future<void> deleteChannelPost({
    required int channelId,
    required int postId,
  }) async {
    final token = await AuthService.getAccessToken();
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
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to delete post');
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
  }) async {
    final token = await AuthService.getAccessToken();
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
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create post');
    }
  }

  /// Обновить роль участника канала
  static Future<void> updateChannelMemberRole({
    required int channelId,
    required int userId,
    required String role, // 'admin', 'moderator', 'member'
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/members/$userId');
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

  /// Удалить участника из канала
  static Future<void> removeChannelMember({
    required int channelId,
    required int userId,
  }) async {
    final token = await AuthService.getAccessToken();
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
    final token = await AuthService.getAccessToken();
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

    if (response.statusCode != 200) {
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
  final String? category;
  final int membersCount;
  final int postsCount;
  final DateTime createdAt;
  final bool autoPublishReels;

  Channel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.coverUrl,
    this.avatarUrl,
    required this.adminUserId,
    required this.isPublic,
    this.category,
    required this.membersCount,
    required this.postsCount,
    required this.createdAt,
    required this.autoPublishReels,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      coverUrl: json['cover_url'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      adminUserId: json['admin_user_id'] as int,
      isPublic: json['is_public'] as bool,
      category: json['category'] as String?,
      membersCount: json['members_count'] as int,
      postsCount: json['posts_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      autoPublishReels: json['auto_publish_reels'] as bool? ?? true,
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
  final bool? autoPublishToMenu;
  final bool? allowComments;
  final bool? allowLikes;
  final bool? allowReposts;

  ChannelDetail({
    required super.id,
    required super.name,
    required super.slug,
    super.description,
    super.coverUrl,
    super.avatarUrl,
    required super.adminUserId,
    required super.isPublic,
    super.category,
    required super.membersCount,
    required super.postsCount,
    required super.createdAt,
    required super.autoPublishReels,
    this.adminUser,
    required this.isMember,
    required this.isAdmin,
    required this.isOwner,
    required this.isModerator,
    this.tags,
    this.rules,
    this.autoPublishToFeed,
    this.autoPublishToMenu,
    this.allowComments,
    this.allowLikes,
    this.allowReposts,
  });

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      coverUrl: json['cover_url'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      adminUserId: json['admin_user_id'] as int,
      isPublic: json['is_public'] as bool,
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
      autoPublishToMenu: json['auto_publish_to_menu'] as bool?,
      allowComments: json['allow_comments'] as bool?,
      allowLikes: json['allow_likes'] as bool?,
      allowReposts: json['allow_reposts'] as bool?,
    );
  }

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
      'auto_publish_to_menu': autoPublishToMenu,
      'allow_comments': allowComments,
      'allow_likes': allowLikes,
      'allow_reposts': allowReposts,
    };
  }
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

class JoinChannelResponse {
  final bool joined;
  final int membersCount;

  JoinChannelResponse({
    required this.joined,
    required this.membersCount,
  });

  factory JoinChannelResponse.fromJson(Map<String, dynamic> json) {
    return JoinChannelResponse(
      joined: json['joined'] as bool,
      membersCount: json['members_count'] as int,
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
