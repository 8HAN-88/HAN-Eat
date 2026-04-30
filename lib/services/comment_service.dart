// Сервис для работы с комментариями
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class CommentService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Получить комментарии к посту
  static Future<CommentsResponse> getComments(int postId, {int limit = 20, int offset = 0}) async {
    final token = await AuthService.getAccessToken();
    
    final uri = Uri.parse('$baseUrl/posts/$postId/comments').replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.get(uri, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CommentsResponse.fromJson(data);
    } else {
      throw Exception('Failed to load comments');
    }
  }
  
  /// Создать комментарий
  static Future<Comment> createComment(int postId, String text, {int? parentId}) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/comments');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': text,
        if (parentId != null) 'parent_id': parentId,
      }),
    );
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Comment.fromJson(data);
    } else {
      final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
      final errorMessage = errorData?['detail'] as String? ?? 'Failed to create comment';
      throw Exception(errorMessage);
    }
  }
  
  /// Удалить комментарий
  static Future<void> deleteComment(int commentId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/comments/$commentId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode != 204) {
      throw Exception('Failed to delete comment');
    }
  }
}

class CommentsResponse {
  final List<Comment> comments;
  final int total;
  
  CommentsResponse({
    required this.comments,
    required this.total,
  });
  
  factory CommentsResponse.fromJson(Map<String, dynamic> json) {
    return CommentsResponse(
      comments: (json['comments'] as List<dynamic>)
          .map((item) => Comment.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

class Comment {
  final int id;
  final int postId;
  final int userId;
  final String text;
  final int? parentId;
  final DateTime createdAt;
  final String? authorName;
  final String? authorAvatar;
  
  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.text,
    this.parentId,
    required this.createdAt,
    this.authorName,
    this.authorAvatar,
  });
  
  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      userId: json['user_id'] as int,
      text: json['text'] as String,
      parentId: json['parent_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      authorName: json['author_name'] as String?,
      authorAvatar: json['author_avatar'] as String?,
    );
  }
}

