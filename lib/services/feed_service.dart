// Сервис для работы с лентой
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/post_model.dart';
import '../models/post_types.dart';
import 'auth_service.dart';
import 'server_config.dart';

class FeedService {
  // Используем общий конфиг для определения базового URL
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  /// Получить ленту постов
  static Future<FeedResponse> getFeed({
    String? cursor,
    int limit = 20,
    String feedType = 'all',
    bool followingOnly = false,
  }) async {
    try {
      var token = await AuthService.getAccessToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final uri = Uri.parse('$baseUrl/feed').replace(queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit.toString(),
        'feed_type': feedType,
        'following_only': followingOnly.toString(),
      });

      var headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      var response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Превышено время ожидания ответа от сервера'),
      );

      // При 401 пробуем обновить токен и повторить запрос
      if (response.statusCode == 401) {
        try {
          token = await AuthService.refreshToken();
          headers['Authorization'] = 'Bearer $token';
          response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Превышено время ожидания ответа от сервера'),
          );
        } catch (_) {
          throw Exception('Сессия истекла. Войдите снова.');
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FeedResponse.fromJson(data);
      } else {
        throw Exception('Failed to load feed: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in getFeed: $e');
      }
      // При ошибке подключения возвращаем пустой ответ
      if (e is TimeoutException || 
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch')) {
        return FeedResponse(items: [], nextCursor: null, hasMore: false);
      }
      rethrow;
    }
  }
  
  /// Получить главную ленту (алиас для getFeed с параметрами)
  static Future<List<PostModel>> getMainFeed({
    required FeedSortMode mode,
    int limit = 20,
    String? lastPostId,
  }) async {
    try {
      final response = await getFeed(
        cursor: lastPostId,
        limit: limit,
        feedType: mode.value,
      );
      return response.items;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in getMainFeed: $e');
      }
      // При ошибке возвращаем пустой список
      return [];
    }
  }
  
  /// Лайкнуть пост
  static Future<void> likePost(int postId, String userId) async {
    // TODO: Реализовать через API
    throw UnimplementedError('likePost not implemented');
  }
  
  /// Убрать лайк с поста
  static Future<void> unlikePost(int postId, String userId) async {
    // TODO: Реализовать через API
    throw UnimplementedError('unlikePost not implemented');
  }
  
  /// Скрыть пост
  static Future<void> hidePost(String postId, String userId) async {
    // TODO: Реализовать через API
    throw UnimplementedError('hidePost not implemented');
  }
  
  /// Пожаловаться на пост
  static Future<void> reportPost(String postId, String userId, String reason) async {
    // TODO: Реализовать через API
    throw UnimplementedError('reportPost not implemented');
  }
}

class FeedResponse {
  final List<PostModel> items;
  final String? nextCursor;
  final bool hasMore;
  
  FeedResponse({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });
  
  factory FeedResponse.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>? ?? [];
    final posts = <PostModel>[];
    for (final item in itemsList) {
      try {
        if (item is Map<String, dynamic>) {
          posts.add(PostModel.fromJson(item));
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error parsing post: $e, item: $item');
        }
        // Пропускаем невалидный пост, чтобы остальные отобразились
      }
    }
    return FeedResponse(
      items: posts,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
