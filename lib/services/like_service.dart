// Сервис для работы с лайками
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/network/haneat_http_client.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class LikeService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static Future<String> _requireToken() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) {
      throw const ApiClientException(message: 'Войдите в аккаунт');
    }
    return token;
  }

  static Future<http.Response> _postWithAuthRetry(Uri uri) async {
    var token = await _requireToken();
    var response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await HanEatHttpClient.withShared(
        (client) => client.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
    }
    return response;
  }

  static Future<http.Response> _deleteWithAuthRetry(Uri uri) async {
    var token = await _requireToken();
    var response = await HanEatHttpClient.withShared(
      (client) => client.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await HanEatHttpClient.withShared(
        (client) => client.delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
    }
    return response;
  }

  static Future<http.Response> _getWithAuthRetry(Uri uri) async {
    var token = await _requireToken();
    var response = await HanEatHttpClient.withShared(
      (client) => client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await HanEatHttpClient.withShared(
        (client) => client.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
    }
    return response;
  }

  static Never _throwLikeError(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  /// Лайкнуть пост
  static Future<LikeResponse> likePost(int postId) async {
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
    final response = await _postWithAuthRetry(uri);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LikeResponse.fromJson(data);
    }
    if (response.statusCode == 400) {
      final statusResponse = await getLikeStatus(postId);
      return LikeResponse(
        liked: true,
        likesCount: statusResponse.likesCount,
      );
    }
    _throwLikeError(response, 'Не удалось поставить лайк');
  }

  /// Убрать лайк
  static Future<LikeResponse> unlikePost(int postId) async {
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
    final response = await _deleteWithAuthRetry(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LikeResponse.fromJson(data);
    }
    if (response.statusCode == 404) {
      final statusResponse = await getLikeStatus(postId);
      return LikeResponse(
        liked: false,
        likesCount: statusResponse.likesCount,
      );
    }
    _throwLikeError(response, 'Не удалось убрать лайк');
  }

  /// Проверить статус лайка
  static Future<LikeResponse> getLikeStatus(int postId) async {
    final uri = Uri.parse('$baseUrl/posts/$postId/like/status');
    final response = await _getWithAuthRetry(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LikeResponse.fromJson(data);
    }
    _throwLikeError(response, 'Не удалось получить статус лайка');
  }

  /// Список пользователей, которым понравился пост.
  static Future<PostLikersPage> listLikers(
    int postId, {
    int limit = 40,
    int? cursor,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor > 0) 'cursor': '$cursor',
    };
    final uri = Uri.parse('$baseUrl/posts/$postId/likes').replace(
      queryParameters: params,
    );
    final response = await _getWithAuthRetry(uri);
    if (response.statusCode == 200) {
      return PostLikersPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwLikeError(response, 'Не удалось загрузить отметки «Нравится»');
  }
}

class LikeResponse {
  final bool liked;
  final int likesCount;

  LikeResponse({
    required this.liked,
    required this.likesCount,
  });

  factory LikeResponse.fromJson(Map<String, dynamic> json) {
    return LikeResponse(
      liked: json['liked'] as bool,
      likesCount: json['likes_count'] as int,
    );
  }
}

class PostLiker {
  const PostLiker({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.likeId,
  });

  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final int? likeId;

  factory PostLiker.fromJson(Map<String, dynamic> json) {
    return PostLiker(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Пользователь',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      likeId: (json['like_id'] as num?)?.toInt(),
    );
  }
}

class PostLikersPage {
  const PostLikersPage({
    required this.items,
    required this.total,
    this.nextCursor,
  });

  final List<PostLiker> items;
  final int total;
  final int? nextCursor;

  factory PostLikersPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return PostLikersPage(
      items: raw
          .whereType<Map>()
          .map((e) => PostLiker.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id > 0)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      nextCursor: (json['next_cursor'] as num?)?.toInt(),
    );
  }
}
