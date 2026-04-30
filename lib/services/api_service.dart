import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' if (dart.library.html) 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_mode.dart';
import '../models/analysis_result.dart';
import '../models/community_video.dart';
import '../models/recipe.dart';
import '../models/search_history_entry.dart';

import 'server_config.dart';
import 'auth_service.dart';

class ApiService {
  // Используем общий конфиг для определения базового URL
  static String get baseUrl => ServerConfig.baseUrl;
  
  // Для реальных устройств можно использовать переменную окружения
  // или настройку в приложении. По умолчанию используем автоматическое определение.
  static String? _customBaseUrl;
  static void setBaseUrl(String? url) => _customBaseUrl = url;
  
  static String get _effectiveBaseUrl => _customBaseUrl ?? baseUrl;

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    // Убеждаемся, что путь начинается с /api/v1
    final fullPath = path.startsWith('/api/v1') ? path : '/api/v1$path';
    return Uri.parse('$_effectiveBaseUrl$fullPath').replace(queryParameters: query);
  }
  
  // Публичные методы для использования в других сервисах
  static Uri uri(String path, [Map<String, dynamic>? query]) => _uri(path, query);
  static Map<String, String> get jsonHeaders => _jsonHeaders;

  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  static Future<List<Recipe>> searchRecipes(
    String ingredients, {
    required AnalysisMode mode,
    required String language,
    Map<String, dynamic>? filters,
    List<String>? tags, // Теги категорий для Spoonacular
    int? maxReadyTime, // Макс. время готовки в минутах (фильтр)
  }) async {
    try {
      final body = <String, dynamic>{
        'ingredients': ingredients,
        'mode': mode.apiValue,
        'language': language,
        if (filters != null) 'filters': filters,
        if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
        if (maxReadyTime != null && maxReadyTime > 0) 'max_ready_time': maxReadyTime,
      };
      
      final resp = await http.post(
        _uri('/recipes'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Превышено время ожидания ответа от сервера');
      });
      _ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['recipes'] as List<dynamic>? ?? [];
      return list.map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in searchRecipes: $e');
      }
      // Возвращаем пустой список при ошибке подключения к серверу
      if (e is TimeoutException || 
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('ClientException')) {
        if (kDebugMode) {
          debugPrint('Server connection error, returning empty list');
        }
        return [];
      }
      rethrow;
    }
  }

  static Future<List<Recipe>> fetchRecommendations({
    int limit = 6,
    String? tags,
    String? ingredients,
    AnalysisMode? mode,
    String? language,
  }) async {
    Future<List<Recipe>> doFetch({
      required int limit,
      String? tags,
      String? ingredients,
      String? modeVal,
      String? language,
    }) async {
      final query = <String, String>{'limit': '$limit'};
      if (tags != null && tags.isNotEmpty) query['tags'] = tags;
      if (ingredients != null && ingredients.isNotEmpty) query['ingredients'] = ingredients;
      if (modeVal != null && modeVal.isNotEmpty) query['mode'] = modeVal;
      if (language != null && language.isNotEmpty) query['language'] = language;
      final resp = await http.get(_uri('/recommendations', query))
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Превышено время ожидания ответа от сервера');
      });
      _ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['recipes'] as List<dynamic>? ?? [];
      final out = <Recipe>[];
      for (final item in list) {
        try {
          final map = item is Map<String, dynamic> ? item : (item is Map ? Map<String, dynamic>.from(item as Map) : null);
          if (map == null) continue;
          out.add(Recipe.fromJson(map));
        } catch (parseError) {
          if (kDebugMode) debugPrint('fetchRecommendations skip recipe: $parseError');
        }
      }
      return out;
    }

    try {
      final recipes = await doFetch(
        limit: limit,
        tags: tags,
        ingredients: ingredients,
        modeVal: mode?.apiValue,
        language: language,
      );
      if (recipes.isNotEmpty) return recipes;
      // Повторная попытка без тегов/ингредиентов — часто даёт результат с бэкенда
      final fallback = await doFetch(
        limit: limit,
        tags: null,
        ingredients: null,
        modeVal: mode?.apiValue,
        language: language ?? 'ru',
      );
      return fallback;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in fetchRecommendations: $e');
      }
      if (e is TimeoutException ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('ClientException')) {
        if (kDebugMode) debugPrint('Server connection error, returning empty list');
        return [];
      }
      rethrow;
    }
  }

  static Future<AnalysisResult> analyzePhoto(
    Uint8List imageBytes, {
    required AnalysisMode mode,
    required String language,
  }) async {
    final resp = await http.post(
      _uri('/analyze'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'image_base64': base64Encode(imageBytes),
        'mode': mode.apiValue,
        'language': language,
      }),
    );
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final analysis = data['analysis'] as Map<String, dynamic>;
    return AnalysisResult.fromJson(analysis);
  }

  static Future<Map<String, dynamic>> fetchSettings() async {
    final resp = await http.get(_uri('/settings'));
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<void> updateSettings({
    AnalysisMode? mode,
    String? language,
  }) async {
    final payload = <String, dynamic>{};
    if (mode != null) payload['analysis_mode'] = mode.apiValue;
    if (language != null) payload['language'] = language;
    final resp = await http.post(
      _uri('/settings'),
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    _ensureSuccess(resp);
  }

  /// Получить рецепт по ID (для открытия по ссылке haneat://recipe/id).
  static Future<Recipe?> getRecipeById(int id, {String? language}) async {
    try {
      final path = '/recipes/$id';
      final uri = (language != null && language.isNotEmpty)
          ? _uri(path, {'language': language})
          : _uri(path);
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return Recipe.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('getRecipeById error: $e');
      return null;
    }
  }

  static Future<List<Recipe>> getFavorites() async {
    final resp = await http.get(_uri('/favorites'));
    _ensureSuccess(resp);
    final Map<String, dynamic> data = jsonDecode(resp.body);
    final list = (data['favorites'] as List<dynamic>?) ?? [];
    return list.map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> addFavorite(Recipe r) async {
    final resp = await http.post(
      _uri('/favorites'),
      headers: _jsonHeaders,
      body: jsonEncode({'recipe': r.toJson()}),
    );
    _ensureSuccess(resp);
  }

  static Future<void> removeFavorite(int id) async {
    final resp = await http.delete(_uri('/favorites/$id'));
    _ensureSuccess(resp);
  }

  static Future<void> clearServerHistory() async {
    final resp = await http.delete(_uri('/history'));
    _ensureSuccess(resp);
  }

  static Future<List<SearchHistoryEntry>> fetchHistory({int limit = 25}) async {
    final resp = await http.get(_uri('/history', {'limit': '$limit'}));
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['history'] as List<dynamic>? ?? [];
    return list.map((entry) {
      final ts = entry['ts'] as int? ?? 0;
      final iso =
          DateTime.fromMillisecondsSinceEpoch(ts * 1000).toIso8601String();
      return SearchHistoryEntry.fromMap({
        'query': entry['query'],
        'timestamp': iso,
        'mode': entry['mode'],
      });
    }).toList();
  }

  static Future<List<CommunityVideo>> fetchCommunityVideos({String? tag}) async {
    try {
      final query = <String, String>{};
      if (tag != null && tag.isNotEmpty) {
        query['tag'] = tag;
      }
      final resp = await http.get(_uri('/community', query))
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Превышено время ожидания ответа от сервера');
      });
      _ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['videos'] as List<dynamic>? ?? [];
      return list
          .map((e) => CommunityVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in fetchCommunityVideos: $e');
      }
      // Возвращаем пустой список при ошибке подключения к серверу
      if (e is TimeoutException || 
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('ClientException')) {
        if (kDebugMode) {
          debugPrint('Server connection error, returning empty list');
        }
        return [];
      }
      rethrow;
    }
  }

  static Future<int> likeCommunityVideo(int id) async {
    final resp = await http.post(_uri('/community/$id/like'));
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['likes'] as int? ?? 0;
  }

  static Future<CommunityVideo> uploadCommunityVideo({
    required String title,
    required String author,
    required String description,
    required List<String> tags,
    required String videoBase64,
    String? thumbnailBase64,
    String? avatar,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Войдите в аккаунт, чтобы загрузить видео');
    }
    final headers = <String, String>{
      ..._jsonHeaders,
      'Authorization': 'Bearer $token',
    };
    final resp = await http.post(
      _uri('/community'),
      headers: headers,
      body: jsonEncode({
        'title': title,
        'author': author,
        'description': description,
        'tags': tags,
        'video_base64': videoBase64,
        'thumbnail_base64': thumbnailBase64,
        'avatar': avatar,
        'status': 'pending',
      }),
    );
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CommunityVideo.fromJson(data['video'] as Map<String, dynamic>);
  }

  static void _ensureSuccess(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Special handling for Spoonacular API limit errors
      if (resp.statusCode == 402) {
        final body = resp.body;
        if (body.contains('daily points limit') || body.contains('points limit')) {
          throw Exception(
            'Достигнут дневной лимит запросов к API Spoonacular (50 запросов). '
            'Пожалуйста, обновите план подписки или попробуйте позже.',
          );
        }
      }
      throw Exception('API error ${resp.statusCode}: ${resp.body}');
    }
  }
  
  // Публичный метод для использования в других сервисах
  static void ensureSuccess(http.Response resp) => _ensureSuccess(resp);
}
