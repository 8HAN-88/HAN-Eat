import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

class RecipeComment {
  final int id;
  final String recipeId;
  final String author;
  final String? authorAvatar;
  final String? authorId;  // ID автора для проверки прав удаления
  final String text;
  final int? rating;  // Рейтинг от 1 до 5
  final int createdAt;

  RecipeComment({
    required this.id,
    required this.recipeId,
    required this.author,
    this.authorAvatar,
    this.authorId,
    required this.text,
    this.rating,
    required this.createdAt,
  });

  factory RecipeComment.fromJson(Map<String, dynamic> json) {
    return RecipeComment(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      recipeId: json['recipe_id']?.toString() ?? '',
      author: json['author']?.toString() ?? 'Anonymous',
      authorAvatar: json['author_avatar']?.toString(),
      authorId: json['author_id']?.toString(),
      text: json['text']?.toString() ?? '',
      rating: json['rating'] is int ? json['rating'] : (json['rating'] != null ? int.tryParse('${json['rating']}') : null),
      createdAt: json['created_at'] is int ? json['created_at'] : int.tryParse('${json['created_at']}') ?? 0,
    );
  }
}

class RecipeCommentsService {
  static Future<List<RecipeComment>> getComments(String recipeId) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/comments');
      final resp = await http.get(uri, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final comments = data['comments'] as List<dynamic>? ?? [];
      return comments
          .map((e) => RecipeComment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error fetching comments: $e');
      return [];
    }
  }

  static Future<RecipeComment?> addComment(
    String recipeId,
    String author,
    String text, {
    String? authorAvatar,
    String? authorId,
    int? rating,
  }) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/comments');
      final body = {
        'author': author,
        'text': text,
        if (authorAvatar != null) 'author_avatar': authorAvatar,
        if (authorId != null) 'author_id': authorId,
        if (rating != null) 'rating': rating,
      };
      
      // Добавляем токен авторизации, если он есть
      final headers = Map<String, String>.from(ApiService.jsonHeaders);
      final token = await AuthService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      
      final resp = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // Backend возвращает {"ok": True, "comment": {...}}
      final commentData = data['comment'] as Map<String, dynamic>?;
      if (commentData != null) {
        return RecipeComment.fromJson(commentData);
      }
      // Если формат другой, пытаемся распарсить весь ответ
      return RecipeComment.fromJson(data);
    } catch (e) {
      print('Error adding comment: $e');
      return null;
    }
  }

  static Future<bool> deleteComment(
    String recipeId,
    int commentId, {
    String? authorId,
  }) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/comments/$commentId');
      final queryParams = <String, String>{};
      if (authorId != null) {
        queryParams['author_id'] = authorId;
      }
      final uriWithParams = uri.replace(queryParameters: queryParams);
      final resp = await http.delete(uriWithParams, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      return true;
    } catch (e) {
      print('Error deleting comment: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getRecipeRating(String recipeId) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/rating');
      final resp = await http.get(uri, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'rating': (data['rating'] as num?)?.toDouble() ?? 0.0,
        'count': (data['count'] as int?) ?? 0,
      };
    } catch (e) {
      print('Error fetching recipe rating: $e');
      return {'rating': 0.0, 'count': 0};
    }
  }
}

