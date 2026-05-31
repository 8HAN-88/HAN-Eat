// Сервис для работы с постами
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post.dart' show PollData, PollVotersResponse;
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class PostService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  /// Создать пост
  static Future<Post> createPost({
    required String type,
    String? title,
    String? description,
    List<String>? tags,
    String? visibility,
    int? channelId,
    List<Map<String, String>>? media,
    List<String>? publishTo,
    String? linkUrl,
    String? linkPreview,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': type,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
        if (visibility != null) 'visibility': visibility,
        if (channelId != null) 'channel_id': channelId,
        if (media != null) 'media': media,
        if (publishTo != null) 'publish_to': publishTo,
        if (type == 'link' && linkUrl != null)
          'link': {
            'url': linkUrl,
            if (linkPreview != null && linkPreview.isNotEmpty)
              'preview': linkPreview,
          },
      }),
    );
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось создать пост',
    );
  }

  /// Live-preview для ссылки (title/description/image/domain).
  static Future<Map<String, dynamic>> fetchLinkPreview(String url) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    final uri = Uri.parse('$baseUrl/posts/link/preview');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'url': url}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['meta'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось загрузить превью ссылки',
    );
  }

  /// Создать пост-опрос
  static Future<Post> createPoll({
    required String question,
    required List<String> options,
    String? description,
    int? channelId,
    List<String>? tags,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'poll',
        if (description != null && description.isNotEmpty)
          'description': description,
        if (channelId != null) 'channel_id': channelId,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        'poll': {
          'question': question,
          'options': options,
        },
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось создать опрос',
    );
  }

  /// Проголосовать в опросе (вернёт обновлённый poll в body)
  static Future<PollData> votePoll({
    required int postId,
    required int optionIndex,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts/$postId/poll/vote');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'option_index': optionIndex}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final poll = data['poll'] as Map<String, dynamic>?;
      if (poll != null) {
        return PollData.fromJson(poll);
      }
      throw Exception('Invalid poll response');
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось проголосовать',
    );
  }

  /// Закрыть опрос (автор поста).
  static Future<PollData> closePoll({required int postId}) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts/$postId/poll/close');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final poll = data['poll'] as Map<String, dynamic>?;
      if (poll != null) {
        return PollData.fromJson(poll);
      }
      throw Exception('Invalid poll response');
    }

    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось закрыть опрос',
    );
  }

  /// Список проголосовавших по вариантам опроса.
  static Future<PollVotersResponse> getPollVoters({required int postId}) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts/$postId/poll/voters');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return PollVotersResponse.fromJson(data);
    }

    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось загрузить список голосов',
    );
  }
  
  /// Создать рецепт в профиле
  static Future<Post> createRecipe({
    required String title,
    String? description,
    required List<String> ingredients,
    required List<Map<String, dynamic>> steps, // [{number: int, text: String, image_url?: String}]
    List<Map<String, dynamic>>? media, // [{type: 'image'|'video', url: String}]
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    List<String>? tags,
    String? visibility,
    int? channelId,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts');
    
    final body = <String, dynamic>{
      'type': 'recipe',
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      'ingredients': ingredients,
      'steps': steps,
      if (prepTimeMin != null) 'prep_time_min': prepTimeMin,
      if (cookTimeMin != null) 'cook_time_min': cookTimeMin,
      if (servings != null) 'servings': servings,
      if (calories != null) 'calories': calories,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbsG != null) 'carbs_g': carbsG,
      if (fatG != null) 'fat_g': fatG,
      if (fiberG != null) 'fiber_g': fiberG,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (media != null && media.isNotEmpty) 'media': media,
      if (visibility != null) 'visibility': visibility,
      if (channelId != null) 'channel_id': channelId,
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось создать рецепт',
    );
  }
  
  /// Получить пост
  static Future<Post> getPost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    
    final uri = Uri.parse('$baseUrl/posts/$postId');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.get(uri, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    } else {
      throw Exception('Failed to load post');
    }
  }
  
  /// Удалить пост профиля (мягкое удаление на сервере).
  static Future<void> deletePost(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts/$postId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
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

  /// Обновить пост
  static Future<Post> updatePost({
    required int postId,
    String? title,
    String? description,
    List<String>? tags,
    List<Map<String, String>>? media,
    List<String>? ingredients,
    List<Map<String, dynamic>>? steps,
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
    String? linkUrl,
    String? linkPreview,
    String? pollQuestion,
    List<String>? pollOptions,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId');
    final body = <String, dynamic>{};
    
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (tags != null) body['tags'] = tags;
    if (media != null) body['media'] = media;
    if (ingredients != null) body['ingredients'] = ingredients;
    if (steps != null) body['steps'] = steps;
    if (prepTimeMin != null) body['prep_time_min'] = prepTimeMin;
    if (cookTimeMin != null) body['cook_time_min'] = cookTimeMin;
    if (servings != null) body['servings'] = servings;
    if (calories != null) body['calories'] = calories;
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
    
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось обновить пост',
    );
  }
}

// Временная модель поста
class Post {
  final int id;
  final String type;
  final String? title;
  final String? description;
  final String status;
  final DateTime createdAt;
  final int userId;
  final int? communityId;
  final Map<String, dynamic>? body;
  final List<String>? tags;
  
  Post({
    required this.id,
    required this.type,
    this.title,
    this.description,
    required this.status,
    required this.createdAt,
    required this.userId,
    this.communityId,
    this.body,
    this.tags,
  });
  
  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userId: json['user_id'] as int,
      communityId: json['community_id'] as int? ?? json['channel_id'] as int?,
      body: json['body'] as Map<String, dynamic>?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'user_id': userId,
        'channel_id': communityId,
        'community_id': communityId,
        'body': body,
        'tags': tags,
        'likes_count': 0,
        'comments_count': 0,
        'reposts_count': 0,
        'is_liked': false,
      };
}

