// Сервис для работы с лайками
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class LikeService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Лайкнуть пост
  static Future<LikeResponse> likePost(int postId) async {
    var token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
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
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LikeResponse.fromJson(data);
    } else if (response.statusCode == 400) {
      // Лайк уже поставлен - получаем актуальное состояние
      final statusResponse = await getLikeStatus(postId);
      return statusResponse;
    } else {
      final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
      final errorMessage = errorData?['detail'] as String? ?? 'Failed to like post';
      throw Exception(errorMessage);
    }
  }
  
  /// Убрать лайк
  static Future<LikeResponse> unlikePost(int postId) async {
    var token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
    var response = await http.delete(
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
        response = await http.delete(
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
      return LikeResponse.fromJson(data);
    } else if (response.statusCode == 404) {
      // Лайк уже убран - получаем актуальное состояние
      final statusResponse = await getLikeStatus(postId);
      return statusResponse;
    } else {
      final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
      final errorMessage = errorData?['detail'] as String? ?? 'Failed to unlike post';
      throw Exception(errorMessage);
    }
  }
  
  /// Проверить статус лайка
  static Future<LikeResponse> getLikeStatus(int postId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/like/status');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LikeResponse.fromJson(data);
    } else {
      throw Exception('Failed to get like status');
    }
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

