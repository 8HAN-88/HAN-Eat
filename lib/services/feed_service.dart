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

  // Бэкенд принимает feed_type: all|reels|recipes|photos.
  // UI-режимы (personalized/recent/popular/trending) пока маппим в all.
  static String _toBackendFeedType(FeedSortMode mode) {
    switch (mode) {
      case FeedSortMode.personalized:
      case FeedSortMode.recent:
      case FeedSortMode.popular:
      case FeedSortMode.trending:
        return 'all';
    }
  }
  
  /// Получить ленту постов
  static Future<FeedResponse> getFeed({
    String? cursor,
    int limit = 20,
    String feedType = 'all',
    bool followingOnly = false,
  }) async {
    try {
      var token = await AuthService.getAccessTokenForApi();
      if (token == null) {
        throw Exception('Сессия истекла. Войдите снова.');
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
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('Превышено время ожидания ответа от сервера'),
      );

      // При 401 пробуем обновить токен и повторить запрос
      if (response.statusCode == 401) {
        token = await AuthService.refreshToken();
        headers['Authorization'] = 'Bearer $token';
        response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw TimeoutException('Превышено время ожидания ответа от сервера'),
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FeedResponse.fromJson(data);
      } else {
        throw Exception('Не удалось загрузить ленту (${response.statusCode})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in getFeed: $e');
      }
      // Не подменяем сеть/таймаут пустой лентой — иначе кажется, что «просто нет постов».
      rethrow;
    }
  }
  
  /// Получить главную ленту (алиас для getFeed с параметрами)
  static Future<List<PostModel>> getMainFeed({
    required FeedSortMode mode,
    int limit = 20,
    String? lastPostId,
  }) async {
    final response = await getFeed(
      cursor: lastPostId,
      limit: limit,
      feedType: _toBackendFeedType(mode),
    );
    return response.items;
  }
  
  /// Лайкнуть пост (`POST /posts/{id}/like`).
  static Future<void> likePost(int postId, String userId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт, чтобы ставить лайки');
    }
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 201) return;
    // Уже лайкнут — считаем успехом (идемпотентность UI).
    if (response.statusCode == 400) return;
    throw Exception('Не удалось поставить лайк: ${response.statusCode}');
  }

  /// Убрать лайк (`DELETE /posts/{id}/like`).
  static Future<void> unlikePost(int postId, String userId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    final uri = Uri.parse('$baseUrl/posts/$postId/like');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) return;
    if (response.statusCode == 404) return;
    throw Exception('Не удалось убрать лайк: ${response.statusCode}');
  }

  /// Скрыть пост в ленте: `POST /feed/dismiss` (аналитика + штраф в персональном скоринге).
  static Future<void> hidePost(String postId, String userId) async {
    final id = int.tryParse(postId);
    if (id == null) {
      throw Exception('Некорректный id поста');
    }
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    final uri = Uri.parse('$baseUrl/feed/dismiss');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'post_id': id}),
    );
    if (response.statusCode == 204 || response.statusCode == 200) return;
    if (response.statusCode == 404) {
      throw Exception('Пост не найден');
    }
    throw Exception('Не удалось скрыть пост: ${response.statusCode}');
  }

  /// Пожаловаться на пост (`POST /posts/{id}/report`).
  static Future<void> reportPost(String postId, String userId, String reason) async {
    final id = int.tryParse(postId);
    if (id == null) throw Exception('Некорректный id поста');
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    final uri = Uri.parse('$baseUrl/posts/$id/report');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) return;
    if (response.statusCode == 400) {
      final detail = _tryDetail(response.body);
      throw Exception(detail ?? 'Жалоба не принята');
    }
    throw Exception('Не удалось отправить жалобу: ${response.statusCode}');
  }

  static String? _tryDetail(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>?;
      return m?['detail']?.toString();
    } catch (_) {
      return null;
    }
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
