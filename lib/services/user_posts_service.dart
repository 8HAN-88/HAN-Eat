// Сервис для получения постов пользователя
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post_model.dart';
import 'auth_service.dart';
import 'server_config.dart';

class UserPostsService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  /// Получить посты пользователя
  static Future<UserPostsResponse> getUserPosts({
    required int userId,
    int limit = 20,
    int offset = 0,
    String? postType, // photo | recipe | reel | text
  }) async {
    // Важно: истёкший access JWT даёт на бэкенде current_user=null → репосты на стене
    // фильтруются как для гостя. Обновляем токен по exp и повторяем при 401.
    var token = await AuthService.getAccessTokenForApi();

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    
    if (postType != null) {
      queryParams['post_type'] = postType;
    }
    
    final uri = Uri.parse('$baseUrl/users/$userId/posts').replace(
      queryParameters: queryParams,
    );
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    var response = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('user posts'),
    );

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      headers['Authorization'] = 'Bearer $token';
      response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('user posts'),
      );
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UserPostsResponse.fromJson(data);
    } else {
      throw Exception('Failed to load user posts: ${response.statusCode}');
    }
  }
}

class UserPostsResponse {
  final List<PostModel> posts;
  final int total;
  
  UserPostsResponse({
    required this.posts,
    required this.total,
  });
  
  factory UserPostsResponse.fromJson(Map<String, dynamic> json) {
    return UserPostsResponse(
      posts: (json['posts'] as List<dynamic>)
          .map((item) => PostModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

