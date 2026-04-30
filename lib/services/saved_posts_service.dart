/// Сервис для работы с сохраненными постами (с offline поддержкой)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'api_service.dart';
import '../models/post_model.dart';

class SavedPostsService {
  static String get baseUrl => ApiService.baseUrl + '/api/v1';
  
  static const String _boxName = 'saved_posts';
  static Box<String>? _box;
  static bool _isInitialized = false;
  
  /// Инициализировать локальное хранилище
  static Future<void> init() async {
    if (_isInitialized) return;
    _box = await Hive.openBox<String>(_boxName);
    _isInitialized = true;
  }
  
  /// Проверить подключение к интернету
  static Future<bool> _isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }
  
  /// Сохранить пост (с синхронизацией)
  static Future<void> savePost(dynamic postId) async {
    final postIdInt = postId is int ? postId : int.tryParse(postId.toString());
    if (postIdInt == null) throw Exception('Invalid post ID');
    await savePostById(postIdInt);
  }
  
  /// Сохранить пост по ID (внутренний метод)
  static Future<void> savePostById(int postId) async {
    await init();
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    // Сохраняем локально сразу
    final post = await _getPostById(postId);
    if (post != null) {
      await _savePostLocally(post);
    }
    
    // Пытаемся синхронизировать с сервером
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final uri = Uri.parse('$baseUrl/posts/$postId/save');
        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        
        if (response.statusCode != 201) {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw Exception(error['detail'] ?? 'Failed to save post');
        }
      } catch (e) {
        // Если ошибка сети, пост уже сохранен локально
        debugPrint('Failed to sync save post to server: $e');
      }
    }
  }
  
  /// Получить пост по ID (из API или локального кэша)
  static Future<PostModel?> _getPostById(int postId) async {
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final token = await AuthService.getAccessToken();
        final uri = Uri.parse('$baseUrl/posts/$postId');
        final response = await http.get(
          uri,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return PostModel.fromJson(data);
        }
      } catch (e) {
        debugPrint('Failed to fetch post from API: $e');
      }
    }
    
    // Пытаемся получить из локального кэша
    return _getPostFromLocalCache(postId);
  }
  
  /// Сохранить пост локально
  static Future<void> _savePostLocally(PostModel post) async {
    await init();
    if (_box == null) return;
    final json = jsonEncode(post.toJson());
    await _box!.put('post_${post.id}', json);
  }
  
  /// Получить пост из локального кэша
  static PostModel? _getPostFromLocalCache(int postId) {
    if (_box == null) return null;
    final json = _box!.get('post_$postId');
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return PostModel.fromJson(data);
    } catch (e) {
      debugPrint('Failed to parse cached post: $e');
      return null;
    }
  }
  
  /// Удалить пост из сохраненных (с синхронизацией)
  static Future<void> unsavePost(dynamic postId) async {
    final postIdInt = postId is int ? postId : int.tryParse(postId.toString());
    if (postIdInt == null) throw Exception('Invalid post ID');
    await unsavePostById(postIdInt);
  }
  
  /// Удалить пост из сохраненных по ID (внутренний метод)
  static Future<void> unsavePostById(int postId) async {
    await init();
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    // Удаляем локально сразу
    await _removePostLocally(postId);
    
    // Пытаемся синхронизировать с сервером
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final uri = Uri.parse('$baseUrl/posts/$postId/save');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        
        if (response.statusCode != 200) {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw Exception(error['detail'] ?? 'Failed to unsave post');
        }
      } catch (e) {
        // Если ошибка сети, пост уже удален локально
        debugPrint('Failed to sync unsave post to server: $e');
      }
    }
  }
  
  /// Удалить пост из локального кэша
  static Future<void> _removePostLocally(int postId) async {
    await init();
    if (_box == null) return;
    await _box!.delete('post_$postId');
  }
  
  /// Проверить, сохранен ли пост
  static Future<bool> isPostSaved(int postId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      return false;
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/is_saved');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['is_saved'] as bool? ?? false;
    } else {
      return false;
    }
  }

  /// Сохранить рецепт Spoonacular
  static Future<void> saveRecipe(dynamic recipe) async {
    await init();
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    // Импортируем Recipe для работы с ним
    final recipeId = recipe.id is int ? recipe.id : int.tryParse(recipe.id.toString());
    if (recipeId == null) {
      throw Exception('Invalid recipe ID');
    }
    
    // Преобразуем рецепт в JSON для отправки
    final recipeJson = recipe.toJson();
    
    // Пытаемся синхронизировать с сервером
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final uri = Uri.parse('$baseUrl/recipes/$recipeId/save');
        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(recipeJson),
        );
        
        if (response.statusCode != 201) {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw Exception(error['detail'] ?? 'Failed to save recipe');
        }
      } catch (e) {
        debugPrint('Failed to sync save recipe to server: $e');
        rethrow;
      }
    }
  }

  /// Удалить рецепт Spoonacular из сохраненных
  static Future<void> unsaveRecipe(int recipeId) async {
    await init();
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    // Пытаемся синхронизировать с сервером
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final uri = Uri.parse('$baseUrl/recipes/$recipeId/save');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        
        if (response.statusCode != 200) {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw Exception(error['detail'] ?? 'Failed to unsave recipe');
        }
      } catch (e) {
        debugPrint('Failed to sync unsave recipe to server: $e');
        rethrow;
      }
    }
  }

  /// Проверить, сохранен ли рецепт Spoonacular
  static Future<bool> isRecipeSaved(int recipeId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      return false;
    }
    
    final uri = Uri.parse('$baseUrl/recipes/$recipeId/is_saved');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['is_saved'] as bool? ?? false;
    } else {
      return false;
    }
  }
  
  /// Получить сохраненные посты пользователя (с offline поддержкой)
  static Future<SavedPostsResponse> getSavedPosts({
    required int userId,
    int limit = 20,
    int offset = 0,
    bool forceOnline = false,
    String? postType, // null = все, 'post' = посты, 'reel' = рилсы
  }) async {
    await init();
    final isOnline = await _isOnline();
    
    // Пытаемся получить с сервера, если онлайн
    if (isOnline && !forceOnline) {
      try {
        final token = await AuthService.getAccessToken();
        
        final queryParams = {
          'limit': limit.toString(),
          'offset': offset.toString(),
        };
        if (postType != null) {
          queryParams['post_type'] = postType;
        }
        
        final uri = Uri.parse('$baseUrl/users/$userId/saved').replace(
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
          final result = SavedPostsResponse.fromJson(data);
          
          // Сохраняем посты локально для offline доступа
          for (final post in result.posts) {
            await _savePostLocally(post);
          }
          
          return result;
        }
      } catch (e) {
        debugPrint('Failed to load saved posts from server: $e');
        // Продолжаем с локальным кэшем
      }
    }
    
    // Используем локальный кэш
    return _getSavedPostsFromLocalCache(limit: limit, offset: offset, postType: postType);
  }
  
  /// Получить сохраненные посты из локального кэша
  static SavedPostsResponse _getSavedPostsFromLocalCache({
    int limit = 20,
    int offset = 0,
    String? postType,
  }) {
    if (_box == null) {
      return SavedPostsResponse(posts: [], total: 0);
    }
    
    final posts = <PostModel>[];
    final keys = _box!.keys.where((k) => k.toString().startsWith('post_')).toList();
    
    for (final key in keys) {
      final json = _box!.get(key);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          posts.add(PostModel.fromJson(data));
        } catch (e) {
          debugPrint('Failed to parse cached post: $e');
        }
      }
    }
    
    // Фильтруем по типу поста, если указан
    final filteredPosts = postType != null
        ? posts.where((post) {
            if (postType == 'post') {
              return post.type != 'reel';
            } else if (postType == 'reel') {
              return post.type == 'reel';
            }
            return true;
          }).toList()
        : posts;
    
    // Сортируем по дате создания (новые первыми)
    filteredPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Применяем пагинацию
    final total = filteredPosts.length;
    final start = offset;
    final end = (offset + limit).clamp(0, filteredPosts.length);
    final paginatedPosts = filteredPosts.sublist(start, end);
    
    return SavedPostsResponse(posts: paginatedPosts, total: total);
  }
  
  /// Синхронизировать локальные сохраненные посты с сервером
  static Future<void> syncWithServer() async {
    await init();
    final isOnline = await _isOnline();
    if (!isOnline) return;
    
    final token = await AuthService.getAccessToken();
    if (token == null) return;
    
    final currentUser = await AuthService.getCurrentUser();
    if (currentUser == null) return;
    
    try {
      // Получаем все сохраненные посты с сервера
      final response = await getSavedPosts(
        userId: currentUser.id,
        limit: 1000, // Получаем все для синхронизации
        forceOnline: true,
      );
      
      // Обновляем локальный кэш
      if (_box != null) {
        // Очищаем старые данные
        final keys = _box!.keys.where((k) => k.toString().startsWith('post_')).toList();
        for (final key in keys) {
          await _box!.delete(key);
        }
        
        // Сохраняем новые данные
        for (final post in response.posts) {
          await _savePostLocally(post);
        }
      }
    } catch (e) {
      debugPrint('Failed to sync saved posts: $e');
    }
  }
  
  /// Очистить локальный кэш
  static Future<void> clearLocalCache() async {
    await init();
    if (_box != null) {
      await _box!.clear();
    }
  }
}

class SavedPostsResponse {
  final List<PostModel> posts;
  final int total;
  
  SavedPostsResponse({
    required this.posts,
    required this.total,
  });
  
  factory SavedPostsResponse.fromJson(Map<String, dynamic> json) {
    return SavedPostsResponse(
      posts: (json['posts'] as List<dynamic>)
          .map((item) => PostModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

