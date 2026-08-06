// Сервис для работы с сохраненными постами (с offline поддержкой)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/storage/hive_bootstrap.dart';
import 'auth_service.dart';
import 'api_service.dart';
import '../models/post_model.dart';
import '../features/kitchen/data/models/recipe.dart';
import '../utils/api_error_parser.dart';
import 'feed_cache_service.dart';

class SavedSyncResult {
  const SavedSyncResult({
    required this.success,
    this.fromCache = false,
    this.message,
  });

  final bool success;
  final bool fromCache;
  final String? message;
}

class SavedPostsService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';
  
  static const String _boxName = 'saved_posts';
  static const String _recipesBoxName = 'saved_recipes_v1';
  static const String _detailsBoxName = 'recipe_details_v1';
  static const String _pendingBoxName = 'saved_pending_ops_v1';
  static const String _metaKeyLastSync = 'last_sync_ms';
  static Box<String>? _box;
  static Box<String>? _recipesBox;
  static Box<String>? _detailsBox;
  static Box<String>? _pendingBox;
  static bool _isInitialized = false;
  static DateTime? lastSyncTime;
  static bool lastLoadFromCache = false;
  
  /// Инициализировать локальное хранилище
  static Future<void> init() async {
    if (_isInitialized) return;
    await ensureHiveReady();
    _box = await Hive.openBox<String>(_boxName);
    _recipesBox = await Hive.openBox<String>(_recipesBoxName);
    _detailsBox = await Hive.openBox<String>(_detailsBoxName);
    _pendingBox = await Hive.openBox<String>(_pendingBoxName);
    final syncMs = _box?.get(_metaKeyLastSync);
    if (syncMs is String) {
      final ms = int.tryParse(syncMs);
      if (ms != null) {
        lastSyncTime = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    _isInitialized = true;
  }

  static Future<void> _touchLastSync() async {
    lastSyncTime = DateTime.now();
    await init();
    await _box?.put(
      _metaKeyLastSync,
      lastSyncTime!.millisecondsSinceEpoch.toString(),
    );
  }

  static Future<void> cacheRecipeForOffline(Recipe recipe) async {
    await init();
    if (_detailsBox == null) return;
    await _detailsBox!.put(
      'recipe_${recipe.id}',
      jsonEncode(recipe.toJson()),
    );
  }

  static Future<Recipe?> getOfflineRecipe(int recipeId) async {
    await init();
    if (_detailsBox == null) return null;
    final raw = _detailsBox!.get('recipe_$recipeId');
    if (raw == null) return null;
    try {
      return Recipe.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Failed to parse offline recipe: $e');
      return null;
    }
  }

  static bool _isRecipeLocallySaved(int recipeId) {
    if (_recipesBox?.containsKey('recipe_$recipeId') == true) return true;
    if (_box == null) return false;
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final body = data['body'];
        if (body is Map && body['spoonacular_recipe_id'] == recipeId) {
          return true;
        }
        if (data['source'] == 'spoonacular' && data['id'] == recipeId) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static Future<void> _saveRecipeLocally(int recipeId, Map<String, dynamic> json) async {
    await init();
    await _recipesBox?.put('recipe_$recipeId', jsonEncode(json));
    final post = _spoonacularRecipePost(recipeId, json);
    await _savePostLocally(post);
  }

  static Future<void> _removeRecipeLocally(int recipeId) async {
    await init();
    await _recipesBox?.delete('recipe_$recipeId');
    await _detailsBox?.delete('recipe_$recipeId');
    await _removePostLocally(recipeId);
    if (_box != null) {
      final toDelete = <dynamic>[];
      for (final key in _box!.keys) {
        final raw = _box!.get(key);
        if (raw == null) continue;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final body = data['body'];
          if (body is Map && body['spoonacular_recipe_id'] == recipeId) {
            toDelete.add(key);
          }
        } catch (_) {}
      }
      for (final key in toDelete) {
        await _box!.delete(key);
      }
    }
  }

  static PostModel _spoonacularRecipePost(
    int recipeId,
    Map<String, dynamic> recipeJson,
  ) {
    final ingredients = recipeJson['ingredients'];
    final steps = recipeJson['steps'];
    final image =
        recipeJson['image'] ?? recipeJson['source_image'] ?? recipeJson['imageUrl'];
    return PostModel(
      id: recipeId,
      type: 'recipe',
      title: recipeJson['title'] as String? ?? 'Рецепт',
      description: recipeJson['summary'] as String? ?? '',
      status: 'published',
      createdAt: DateTime.now(),
      userId: AuthService.instance.currentUser?.id ?? 0,
      likesCount: 0,
      commentsCount: 0,
      repostsCount: 0,
      viewsCount: 0,
      isLiked: false,
      body: {
        'ingredients': ingredients is List ? ingredients : [],
        'steps': steps is List ? steps : [],
        'image': image,
        'source_image': image,
        'spoonacular_recipe_id': recipeId,
        'nutrition': recipeJson['nutrition'],
        'calories': recipeJson['calories'],
      },
      isSaved: true,
    );
  }

  static Future<void> _addPendingOp(String op, int id) async {
    await init();
    if (_pendingBox == null) return;
    final key = '${op}_$id';
    await _pendingBox!.put(key, jsonEncode({'op': op, 'id': id}));
  }

  static Future<void> _removePendingOp(String op, int id) async {
    await init();
    await _pendingBox?.delete('${op}_$id');
  }

  static Future<void> processPendingOps() async {
    await init();
    if (_pendingBox == null || !await _isOnline()) return;
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) return;

    for (final key in _pendingBox!.keys.toList()) {
      final raw = _pendingBox!.get(key);
      if (raw == null) continue;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final op = data['op'] as String?;
        final id = data['id'] as int?;
        if (op == null || id == null) continue;
        if (op == 'save_recipe') {
          final recipeJson = _recipesBox?.get('recipe_$id');
          if (recipeJson != null) {
            final uri = Uri.parse('$baseUrl/recipes/$id/save');
            await http.post(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: recipeJson,
            );
          }
        } else if (op == 'unsave_recipe') {
          final uri = Uri.parse('$baseUrl/recipes/$id/save');
          await http.delete(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );
        } else if (op == 'save_post') {
          final uri = Uri.parse('$baseUrl/posts/$id/save');
          await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );
        } else if (op == 'unsave_post') {
          final uri = Uri.parse('$baseUrl/posts/$id/save');
          await http.delete(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );
        }
        await _pendingBox!.delete(key);
      } catch (e) {
        debugPrint('Pending op failed ($key): $e');
      }
    }
  }
  
  /// Проверить подключение к интернету
  static Future<bool> _isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
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
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw const ApiClientException(message: 'Войдите, чтобы сохранить пост');
    }

    final post = await _getPostById(postId);
    if (post != null) {
      await _savePostLocally(post);
    }

    final isOnline = await _isOnline();
    if (!isOnline) {
      await _addPendingOp('save_post', postId);
      return;
    }

    try {
      final uri = Uri.parse('$baseUrl/posts/$postId/save');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 201) {
        return;
      }
      await _removePostLocally(postId);
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromResponse(
        response.statusCode,
        error,
        fallback: 'Не удалось сохранить пост',
      );
    } on ApiClientException {
      await _removePostLocally(postId);
      rethrow;
    } catch (e) {
      await _removePostLocally(postId);
      debugPrint('Failed to sync save post to server: $e');
      throw ApiClientException(message: userVisibleError(e, fallback: 'Не удалось сохранить пост'));
    }
  }
  
  /// Получить пост по ID (из API или локального кэша)
  static Future<PostModel?> _getPostById(int postId) async {
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final token = await AuthService.getAccessTokenForApi();
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
    
    final cached = _getPostFromLocalCache(postId);
    if (cached != null) return cached;

    try {
      final fromFeed = FeedCacheService.instance.getCachedPostModel(postId);
      if (fromFeed != null) return fromFeed;
    } catch (_) {}

    return null;
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
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw const ApiClientException(message: 'Войдите, чтобы убрать из сохранённых');
    }

    final cached = _getPostFromLocalCache(postId);
    await _removePostLocally(postId);

    final isOnline = await _isOnline();
    if (!isOnline) {
      await _addPendingOp('unsave_post', postId);
      return;
    }

    try {
      final uri = Uri.parse('$baseUrl/posts/$postId/save');
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return;
      }
      if (cached != null) {
        await _savePostLocally(cached);
      }
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromResponse(
        response.statusCode,
        error,
        fallback: 'Не удалось убрать из сохранённых',
      );
    } on ApiClientException {
      if (cached != null) {
        await _savePostLocally(cached);
      }
      rethrow;
    } catch (e) {
      if (cached != null) {
        await _savePostLocally(cached);
      }
      debugPrint('Failed to sync unsave post to server: $e');
      throw ApiClientException(
        message: userVisibleError(e, fallback: 'Не удалось убрать из сохранённых'),
      );
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
    if (_getPostFromLocalCache(postId) != null) return true;
    if (!await _isOnline()) return false;

    final token = await AuthService.getAccessTokenForApi();
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
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    // Импортируем Recipe для работы с ним
    final recipeId = recipe.id is int ? recipe.id : int.tryParse(recipe.id.toString());
    if (recipeId == null) {
      throw Exception('Invalid recipe ID');
    }
    
    final recipeJson = recipe.toJson();
    await _saveRecipeLocally(recipeId, recipeJson);
    if (recipe is Recipe) {
      await cacheRecipeForOffline(recipe);
    }

    final isOnline = await _isOnline();
    if (!isOnline) {
      await _addPendingOp('save_recipe', recipeId);
      return;
    }

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
      await _removePendingOp('save_recipe', recipeId);
    } catch (e) {
      await _addPendingOp('save_recipe', recipeId);
      debugPrint('Failed to sync save recipe to server: $e');
      rethrow;
    }
  }

  /// Удалить рецепт Spoonacular из сохраненных
  static Future<void> unsaveRecipe(int recipeId) async {
    await init();
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    await _removeRecipeLocally(recipeId);

    final isOnline = await _isOnline();
    if (!isOnline) {
      await _addPendingOp('unsave_recipe', recipeId);
      return;
    }

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
      await _removePendingOp('unsave_recipe', recipeId);
    } catch (e) {
      await _addPendingOp('unsave_recipe', recipeId);
      debugPrint('Failed to sync unsave recipe to server: $e');
      rethrow;
    }
  }

  /// Проверить, сохранен ли рецепт Spoonacular
  static Future<bool> isRecipeSaved(int recipeId) async {
    if (_isRecipeLocallySaved(recipeId)) return true;
    if (!await _isOnline()) return false;

    final token = await AuthService.getAccessTokenForApi();
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
        final token = await AuthService.getAccessTokenForApi();
        
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
          await _touchLastSync();
          lastLoadFromCache = false;
          return result;
        }
      } catch (e) {
        debugPrint('Failed to load saved posts from server: $e');
      }
    }
    
    lastLoadFromCache = true;
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
  static Future<SavedSyncResult> syncWithServer() async {
    await init();
    final isOnline = await _isOnline();
    if (!isOnline) {
      return const SavedSyncResult(
        success: false,
        message: 'Нет подключения к интернету',
      );
    }

    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      return const SavedSyncResult(
        success: false,
        message: 'Войдите в аккаунт',
      );
    }

    final currentUser = await AuthService.getCurrentUser();
    if (currentUser == null) {
      return const SavedSyncResult(
        success: false,
        message: 'Войдите в аккаунт',
      );
    }

    try {
      await processPendingOps();
      final response = await getSavedPosts(
        userId: currentUser.id,
        limit: 1000,
        forceOnline: true,
      );

      if (_box != null) {
        final keys =
            _box!.keys.where((k) => k.toString().startsWith('post_')).toList();
        for (final key in keys) {
          await _box!.delete(key);
        }
        for (final post in response.posts) {
          await _savePostLocally(post);
        }
      }
      await _touchLastSync();
      lastLoadFromCache = false;
      return const SavedSyncResult(success: true);
    } catch (e) {
      debugPrint('Failed to sync saved posts: $e');
      return SavedSyncResult(
        success: false,
        fromCache: lastLoadFromCache,
        message: userVisibleError(e, fallback: 'Не удалось синхронизировать'),
      );
    }
  }
  
  /// Очистить локальный кэш
  static Future<void> clearLocalCache() async {
    await init();
    await _box?.clear();
    await _recipesBox?.clear();
    await _detailsBox?.clear();
    await _pendingBox?.clear();
    lastSyncTime = null;
    lastLoadFromCache = false;
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

