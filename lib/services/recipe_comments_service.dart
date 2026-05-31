import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart';

class RecipeComment {
  final int id;
  final String recipeId;
  final String author;
  final String? authorAvatar;
  final String? authorId; // ID автора для проверки прав удаления
  final String text;
  final int? parentId; // ID родительского комментария для ответов
  final int? rating; // Рейтинг от 1 до 5
  final int createdAt;

  RecipeComment({
    required this.id,
    required this.recipeId,
    required this.author,
    this.authorAvatar,
    this.authorId,
    required this.text,
    this.parentId,
    this.rating,
    required this.createdAt,
  });

  factory RecipeComment.fromJson(Map<String, dynamic> json) {
    int parseCreatedAt(dynamic value) {
      if (value is int) return value;
      final asString = value?.toString();
      if (asString == null || asString.isEmpty) return 0;
      final parsedInt = int.tryParse(asString);
      if (parsedInt != null) {
        // Если это миллисекунды — приводим к секундам.
        return parsedInt > 2000000000 ? parsedInt ~/ 1000 : parsedInt;
      }
      final parsedDate = DateTime.tryParse(asString);
      if (parsedDate != null) {
        return parsedDate.millisecondsSinceEpoch ~/ 1000;
      }
      return 0;
    }

    return RecipeComment(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      recipeId: (json['recipe_id'] ?? json['post_id'])?.toString() ?? '',
      author: json['author']?.toString() ?? 'Anonymous',
      authorAvatar: json['author_avatar']?.toString(),
      authorId: json['author_id']?.toString(),
      text: (json['text'] ?? json['content'] ?? json['message'])?.toString() ??
          '',
      parentId: json['parent_id'] is int
          ? json['parent_id']
          : (json['parent_id'] != null
              ? int.tryParse('${json['parent_id']}')
              : null),
      rating: json['rating'] is int
          ? json['rating']
          : (json['rating'] != null ? int.tryParse('${json['rating']}') : null),
      createdAt: parseCreatedAt(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recipe_id': recipeId,
      'author': author,
      'author_avatar': authorAvatar,
      'author_id': authorId,
      'text': text,
      'parent_id': parentId,
      'rating': rating,
      'created_at': createdAt,
    };
  }
}

class RecipeCommentsService {
  static String _localCommentsKey(String recipeId) =>
      'recipe_comments_local:$recipeId';

  static Future<List<RecipeComment>> _readLocalComments(String recipeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCommentsKey(recipeId));
      if (raw == null || raw.isEmpty) return const <RecipeComment>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <RecipeComment>[];
      return decoded
          .whereType<Map>()
          .map((e) => RecipeComment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const <RecipeComment>[];
    }
  }

  static Future<void> _writeLocalComments(
    String recipeId,
    List<RecipeComment> comments,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = comments.map((c) => c.toJson()).toList();
      await prefs.setString(_localCommentsKey(recipeId), jsonEncode(payload));
    } catch (_) {
      // ignore local cache write errors
    }
  }

  static Future<List<RecipeComment>> getComments(String recipeId) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/comments');
      final headers = Map<String, String>.from(ApiService.jsonHeaders);
      final token = await AuthService.getAccessTokenForApi();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      final resp = await http.get(uri, headers: headers);
      ApiService.ensureSuccess(resp);
      final decoded = jsonDecode(resp.body);
      final comments = decoded is List<dynamic>
          ? decoded
          : ((decoded as Map<String, dynamic>)['comments'] as List<dynamic>? ??
              (decoded['items'] as List<dynamic>? ?? const <dynamic>[]));
      final remote = comments
          .map((e) => RecipeComment.fromJson(e as Map<String, dynamic>))
          .toList();
      final local = await _readLocalComments(recipeId);
      final byId = <int, RecipeComment>{for (final c in local) c.id: c};
      for (final c in remote) {
        byId[c.id] = c;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _writeLocalComments(recipeId, merged);
      return merged;
    } catch (e) {
      debugPrint('Error fetching comments: $e');
      final local = await _readLocalComments(recipeId);
      local.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return local;
    }
  }

  static Future<RecipeComment?> addComment(
    String recipeId,
    String author,
    String text, {
    String? authorAvatar,
    String? authorId,
    int? parentId,
    int? rating,
  }) async {
    try {
      final uri = ApiService.uri('/recipes/$recipeId/comments');
      final body = {
        'author': author,
        'text': text,
        if (authorAvatar != null) 'author_avatar': authorAvatar,
        if (authorId != null) 'author_id': authorId,
        if (parentId != null) 'parent_id': parentId,
        if (rating != null) 'rating': rating,
      };

      // Добавляем токен авторизации, если он есть
      final headers = Map<String, String>.from(ApiService.jsonHeaders);
      final token = await AuthService.getAccessTokenForApi();
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
        final created = RecipeComment.fromJson(commentData);
        final local = await _readLocalComments(recipeId);
        final merged = <int, RecipeComment>{
          for (final c in local) c.id: c,
          created.id: created,
        }.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _writeLocalComments(recipeId, merged);
        return created;
      }
      // Если формат другой, пытаемся распарсить весь ответ
      final created = RecipeComment.fromJson(data);
      final local = await _readLocalComments(recipeId);
      final merged = <int, RecipeComment>{
        for (final c in local) c.id: c,
        created.id: created,
      }.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _writeLocalComments(recipeId, merged);
      return created;
    } catch (e) {
      debugPrint('Error adding comment: $e');
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
      final resp =
          await http.delete(uriWithParams, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final local = await _readLocalComments(recipeId);
      final filtered = local.where((c) => c.id != commentId).toList();
      await _writeLocalComments(recipeId, filtered);
      return true;
    } catch (e) {
      debugPrint('Error deleting comment: $e');
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
      debugPrint('Error fetching recipe rating: $e');
      return {'rating': 0.0, 'count': 0};
    }
  }
}
