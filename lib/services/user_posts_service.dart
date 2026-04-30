// Сервис для получения постов пользователя
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post_model.dart';
import 'auth_service.dart';

class UserPostsService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Получить посты пользователя
  static Future<UserPostsResponse> getUserPosts({
    required int userId,
    int limit = 20,
    int offset = 0,
    String? postType, // photo | recipe | reel | text
  }) async {
    final token = await AuthService.getAccessToken();
    
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
    
    final response = await http.get(uri, headers: headers);
    
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
      total: json['total'] as int,
    );
  }
}

