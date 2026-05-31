// Сервис для работы с комментариями
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class CommentService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Общее число комментариев (без загрузки всего списка).
  static Future<int> getCommentsTotal(int postId) async {
    final response = await getComments(postId, limit: 1, offset: 0);
    return response.total;
  }

  /// Получить комментарии к посту
  static Future<CommentsResponse> getComments(int postId,
      {int limit = 20, int offset = 0}) async {
    final token = await AuthService.getAccessTokenForApi();

    final uri =
        Uri.parse('$baseUrl/posts/$postId/comments').replace(queryParameters: {
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
      String details = 'Failed to load comments (${response.statusCode})';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final detail = errorData['detail'];
        if (detail != null) {
          details = '$details: $detail';
        }
      } catch (_) {}
      throw Exception(details);
    }
  }

  /// Получить среднюю оценку recipe-поста
  static Future<Map<String, dynamic>> getPostRating(int postId) async {
    final token = await AuthService.getAccessTokenForApi();
    final uri = Uri.parse('$baseUrl/posts/$postId/rating');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'rating': (data['rating'] as num?)?.toDouble() ?? 0.0,
        'count': (data['count'] as int?) ?? 0,
      };
    }
    return {'rating': 0.0, 'count': 0};
  }

  /// Создать комментарий
  static Future<Comment> createComment(
    int postId,
    String text, {
    int? parentId,
    int? rating,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
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
        if (rating != null) 'rating': rating,
        if (parentId != null) 'parent_id': parentId,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Comment.fromJson(data);
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось отправить комментарий',
    );
  }

  /// Удалить комментарий
  static Future<void> deleteComment(int commentId) async {
    final token = await AuthService.getAccessTokenForApi();
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

    if (response.statusCode == 204) {
      return;
    }
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromResponse(
        response.statusCode,
        error,
        fallback: 'Не удалось удалить комментарий',
      );
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
        statusCode: response.statusCode,
        message: 'Не удалось удалить комментарий',
      );
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
  final int? rating;
  final int? parentId;
  final DateTime createdAt;
  final String? authorName;
  final String? authorAvatar;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.text,
    this.rating,
    this.parentId,
    required this.createdAt,
    this.authorName,
    this.authorAvatar,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final rawText = json['text'] ?? json['content'] ?? json['message'] ?? '';
    return Comment(
      id: toInt(json['id']),
      postId: toInt(json['post_id']),
      userId: toInt(json['user_id']),
      text: rawText.toString(),
      rating: json['rating'] != null ? toInt(json['rating']) : null,
      parentId: json['parent_id'] != null ? toInt(json['parent_id']) : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      authorName: json['author_name'] as String?,
      authorAvatar: json['author_avatar'] as String?,
    );
  }
}
