import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_mode.dart';
import '../models/analysis_result.dart';
import '../models/community_video.dart';
import '../models/post_model.dart';
import '../models/recipe.dart';
import '../models/search_history_entry.dart';

import 'server_config.dart';
import 'auth_service.dart';
import '../utils/api_error_parser.dart';

/// Бэкенд вернул 403: нужна подписка с AI (H.A.N. AI или Pro).
/// Алиас для совместимости: раньше «Plus», сейчас AI/Pro.
typedef HanAiRequiredException = HanPlusRequiredException;

class HanPlusRequiredException implements Exception {
  const HanPlusRequiredException([this.message = 'Требуется подписка H.A.N. AI или Pro']);
  final String message;
  @override
  String toString() => message;
}

/// Free tier: cooldown между генерациями AI meal plan.
class HanMealPlanCooldownException implements Exception {
  const HanMealPlanCooldownException([
    this.message = 'Следующий AI meal plan будет доступен позже',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Бэкенд вернул 401: нужен вход в аккаунт.
class HanLoginRequiredException implements Exception {
  const HanLoginRequiredException([this.message = 'Войдите в аккаунт']);
  final String message;
  @override
  String toString() => message;
}

/// Результат загрузки рецепта по ID (404 vs сеть vs успех).
class RecipeLoadResult {
  const RecipeLoadResult({
    this.recipe,
    this.notFound = false,
    this.errorMessage,
  });

  final Recipe? recipe;
  final bool notFound;
  final String? errorMessage;
}

/// Бэкенд: исчерпан банк AI scan (мягкий paywall).
class AiScansExhaustedException implements Exception {
  const AiScansExhaustedException({
    this.isPlus = false,
    this.message,
  });

  final bool isPlus;
  final String? message;
  @override
  String toString() =>
      'Бесплатные AI-сканы закончились. Подключите H.A.N. AI для продолжения';
}

/// Нужен шаг резерва перед /analyze.
class AiScanReserveRequiredException implements Exception {
  const AiScanReserveRequiredException([this.message = 'Сначала забронируйте AI scan']);
  final String message;
  @override
  String toString() => message;
}

/// Сервер без маршрутов `/api/v1/ai-scan/*` (старый процесс или другой сервис на порту).
class AiScanBackendMissingException implements Exception {
  const AiScanBackendMissingException();
  @override
  String toString() =>
      'Сервер не знает эндпоинт AI scan (404). Перезапустите backend из папки '
      'backend: cd backend && alembic upgrade head && '
      'uvicorn app.main:app --reload --host 0.0.0.0 --port 5001';
}

/// Ответ GET /ai-scan/status (без счётчиков в UI).
class AiScanStatus {
  const AiScanStatus({
    required this.canScan,
    required this.softWarning,
    required this.isPlus,
    this.subscriptionType,
  });

  final bool canScan;
  final bool softWarning;
  final bool isPlus;
  final String? subscriptionType;

  factory AiScanStatus.fromJson(Map<String, dynamic> json) {
    final credits = (json['scan_credits'] as num?)?.toInt();
    return AiScanStatus(
      canScan: json['can_scan'] as bool? ?? (credits != null ? credits > 0 : true),
      softWarning: json['soft_warning'] as bool? ??
          json['last_free_warning'] as bool? ??
          false,
      isPlus: json['is_plus'] as bool? ?? false,
      subscriptionType: json['subscription_type'] as String?,
    );
  }
}

/// Ответ POST /ai-scan/reserve.
class AiScanReserveResult {
  const AiScanReserveResult({
    required this.ticket,
    required this.isPlus,
  });

  final String ticket;
  final bool isPlus;

  factory AiScanReserveResult.fromJson(Map<String, dynamic> json) {
    return AiScanReserveResult(
      ticket: json['ticket'] as String,
      isPlus: json['is_plus'] as bool? ?? false,
    );
  }
}

/// Ответ GET /recommendations: список рецептов и признаки от бэкенда.
class RecommendationsResult {
  final List<Recipe> recipes;
  /// Бэкенд: Spoonacular вернул 402 (дневной лимит бесплатного тарифа).
  final bool spoonacularQuotaExhausted;
  /// Зритель с доступом к AI (если передан JWT в запросе).
  final bool viewerIsPlus;
  /// Показать оффер подписки (квота исчерпана и у зрителя нет AI).
  final bool suggestPlusUpgrade;
  /// Бэкенд перевёл карточки на [recipeTranslationLanguage].
  final bool recipeTranslationEnabled;
  /// В ленте есть EN-рецепты, перевод доступен только с AI.
  final bool recipeTranslationRequiresAi;
  final String? recipeTranslationLanguage;
  /// В meta есть поля локализации (старый API без них перевод не отдаёт).
  final bool recipeTranslationApiSupported;

  const RecommendationsResult({
    required this.recipes,
    this.spoonacularQuotaExhausted = false,
    this.viewerIsPlus = false,
    this.suggestPlusUpgrade = false,
    this.recipeTranslationEnabled = false,
    this.recipeTranslationRequiresAi = false,
    this.recipeTranslationLanguage,
    this.recipeTranslationApiSupported = false,
  });
}

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

  static Future<Map<String, String>> authHeaders() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) return _jsonHeaders;
    return {
      ..._jsonHeaders,
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Recipe>> searchRecipes(
    String ingredients, {
    required AnalysisMode mode,
    required String language,
    Map<String, dynamic>? filters,
    List<String>? tags, // Теги категорий для Spoonacular
    int? maxReadyTime, // Макс. время готовки в минутах (фильтр)
    Duration timeout = const Duration(seconds: 60),
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
        headers: await authHeaders(),
        body: jsonEncode(body),
      ).timeout(timeout, onTimeout: () {
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
      rethrow;
    }
  }

  static Future<RecommendationsResult> fetchRecommendations({
    int limit = 6,
    String? tags,
    String? ingredients,
    AnalysisMode? mode,
    String? language,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    Future<RecommendationsResult> doFetch({
      required int limit,
      String? tags,
      String? ingredients,
      String? modeVal,
      String? language,
      bool skipServerCache = false,
    }) async {
      final query = <String, String>{
        'limit': '$limit',
        'quick': 'true', // быстрый путь на бэкенде (без N+1 и без онлайн-перевода)
      };
      if (skipServerCache) query['refresh'] = 'true';
      if (tags != null && tags.isNotEmpty) query['tags'] = tags;
      if (ingredients != null && ingredients.isNotEmpty) query['ingredients'] = ingredients;
      if (modeVal != null && modeVal.isNotEmpty) query['mode'] = modeVal;
      if (language != null && language.isNotEmpty) query['language'] = language;
      // Таймаут запасной: при quick обычно < нескольких секунд.
      final resp = await http.get(
        _uri('/recommendations', query),
        headers: await authHeaders(),
      )
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('Превышено время ожидания ответа от сервера');
      });
      _ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['recipes'] as List<dynamic>? ?? [];
      final meta = data['meta'] as Map<String, dynamic>?;
      final quotaExhausted = meta?['spoonacular_quota_exhausted'] == true;
      final viewerIsPlus = meta?['viewer_is_plus'] == true;
      final suggestPlusUpgrade = meta?['suggest_plus_upgrade'] == true;
      final translationEnabled = meta?['recipe_translation_enabled'] == true;
      final translationRequiresAi =
          meta?['recipe_translation_requires_ai'] == true;
      final translationLanguage =
          meta?['recipe_translation_language'] as String?;
      final translationApiSupported =
          meta != null && meta.containsKey('recipe_translation_language');
      final out = <Recipe>[];
      for (final item in list) {
        try {
          final map = item is Map<String, dynamic> ? item : (item is Map ? Map<String, dynamic>.from(item) : null);
          if (map == null) continue;
          out.add(Recipe.fromJson(map));
        } catch (parseError) {
          if (kDebugMode) debugPrint('fetchRecommendations skip recipe: $parseError');
        }
      }
      return RecommendationsResult(
        recipes: out,
        spoonacularQuotaExhausted: quotaExhausted,
        viewerIsPlus: viewerIsPlus,
        suggestPlusUpgrade: suggestPlusUpgrade,
        recipeTranslationEnabled: translationEnabled,
        recipeTranslationRequiresAi: translationRequiresAi,
        recipeTranslationLanguage: translationLanguage,
        recipeTranslationApiSupported: translationApiSupported,
      );
    }

    const minUsefulCount = 3;

    List<Recipe> mergeRecipes(List<Recipe> a, List<Recipe> b) {
      final seen = <String>{};
      final out = <Recipe>[];
      for (final r in [...a, ...b]) {
        final key = '${r.source ?? ''}|${r.id}|${r.title}';
        if (!seen.add(key)) continue;
        out.add(r);
        if (out.length >= limit) break;
      }
      return out;
    }

    try {
      final first = await doFetch(
        limit: limit,
        tags: tags,
        ingredients: ingredients,
        modeVal: mode?.apiValue,
        language: language,
        skipServerCache: forceRefresh,
      );
      if (kDebugMode) {
        debugPrint(
          'fetchRecommendations: ${first.recipes.length} recipes, '
          'quota=${first.spoonacularQuotaExhausted}, '
          'translated=${first.recipeTranslationEnabled}, '
          'needsAi=${first.recipeTranslationRequiresAi}, '
          'api=${first.recipeTranslationApiSupported}',
        );
      }
      final needsBroaderFetch = first.recipes.length < minUsefulCount ||
          (first.spoonacularQuotaExhausted && first.recipes.length < limit);
      if (!needsBroaderFetch) return first;

      // Повтор без тегов Spoonacular + дополнение локальной базой на бэкенде
      final fallback = await doFetch(
        limit: limit,
        tags: null,
        ingredients: null,
        modeVal: mode?.apiValue,
        language: language ?? 'ru',
        skipServerCache: forceRefresh,
      );
      if (kDebugMode) {
        debugPrint(
          'fetchRecommendations fallback: ${fallback.recipes.length} recipes',
        );
      }
      final merged = mergeRecipes(first.recipes, fallback.recipes);
      return RecommendationsResult(
        recipes: merged,
        spoonacularQuotaExhausted:
            first.spoonacularQuotaExhausted || fallback.spoonacularQuotaExhausted,
        viewerIsPlus: fallback.viewerIsPlus,
        suggestPlusUpgrade:
            first.suggestPlusUpgrade || fallback.suggestPlusUpgrade,
        recipeTranslationEnabled:
            first.recipeTranslationEnabled || fallback.recipeTranslationEnabled,
        recipeTranslationRequiresAi: first.recipeTranslationRequiresAi ||
            fallback.recipeTranslationRequiresAi,
        recipeTranslationLanguage:
            fallback.recipeTranslationLanguage ?? first.recipeTranslationLanguage,
        recipeTranslationApiSupported: first.recipeTranslationApiSupported ||
            fallback.recipeTranslationApiSupported,
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('fetchRecommendations: timeout, retry without tags');
      }
      if (tags != null && tags.isNotEmpty) {
        try {
          return await doFetch(
            limit: limit,
            tags: null,
            ingredients: ingredients,
            modeVal: mode?.apiValue,
            language: language,
            skipServerCache: forceRefresh,
          );
        } on TimeoutException {
          rethrow;
        }
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in fetchRecommendations: $e');
      }
      rethrow;
    }
  }

  static Future<AnalysisResult> analyzePhoto(
    Uint8List imageBytes, {
    required AnalysisMode mode,
    required String language,
    String? aiScanTicket,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final payload = <String, dynamic>{
      'image_base64': base64Encode(imageBytes),
      'mode': mode.apiValue,
      'language': language,
    };
    if (aiScanTicket != null && aiScanTicket.isNotEmpty) {
      payload['ai_scan_ticket'] = aiScanTicket;
    }
    final resp = await http
        .post(
          _uri('/analyze'),
          headers: await authHeaders(),
          body: jsonEncode(payload),
        )
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Превышено время ожидания анализа фото',
          ),
        );
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final analysis = data['analysis'] as Map<String, dynamic>;
    return AnalysisResult.fromJson(analysis);
  }

  /// Резервирует один AI scan на бэкенде (списание кредита) и возвращает JWT для POST /analyze.
  static Future<AiScanReserveResult> reserveAiScan() async {
    final resp = await http
        .post(
          _uri('/ai-scan/reserve'),
          headers: await authHeaders(),
        )
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () =>
              throw TimeoutException('Превышено время ожидания резерва AI scan'),
        );
    if (resp.statusCode == 404) {
      throw const AiScanBackendMissingException();
    }
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AiScanReserveResult.fromJson(data);
  }

  /// Начисление кредитов по суткам без списания (запуск приложения / смена сессии).
  static Future<AiScanStatus?> fetchAiScanStatus() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) return null;
    final resp = await http
        .get(
          _uri('/ai-scan/status'),
          headers: await authHeaders(),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 404) {
      throw const AiScanBackendMissingException();
    }
    _ensureSuccess(resp);
    return AiScanStatus.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  static Future<AiScanStatus?> touchAiScanCreditsSilently() async {
    try {
      final status = await fetchAiScanStatus();
      if (status == null) return null;
      final cached = AuthService.instance.currentUser;
      if (cached != null && status.subscriptionType != null) {
        await AuthService.persistUpdatedUser(
          cached.copyWith(
            subscriptionType: status.subscriptionType,
          ),
        );
      }
      return status;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('touchAiScanCreditsSilently: $e');
      }
      return null;
    }
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
    final result = await loadRecipeById(id, language: language);
    return result.recipe;
  }

  static Future<RecipeLoadResult> loadRecipeById(int id, {String? language}) async {
    try {
      final path = '/recipes/$id';
      final uri = (language != null && language.isNotEmpty)
          ? _uri(path, {'language': language})
          : _uri(path);
      final resp = await http
          .get(uri, headers: await authHeaders())
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 404) {
        return const RecipeLoadResult(notFound: true);
      }
      if (resp.statusCode != 200) {
        return RecipeLoadResult(
          errorMessage: 'Ошибка сервера (${resp.statusCode})',
        );
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return RecipeLoadResult(recipe: Recipe.fromJson(data));
    } on TimeoutException {
      return const RecipeLoadResult(
        errorMessage:
            'Сервер не ответил вовремя. Проверьте подключение и попробуйте снова.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('loadRecipeById error: $e');
      return RecipeLoadResult(
        errorMessage: 'Не удалось загрузить рецепт. Проверьте подключение.',
      );
    }
  }

  /// Получить пост по ID (для deep-link haneat://post/:id).
  static Future<PostModel?> getPostById(int id) async {
    try {
      final uri = _uri('/posts/$id');
      var headers = await authHeaders();
      var resp = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 15),
      );
      if (resp.statusCode == 401) {
        final token = await AuthService.refreshToken();
        headers = {
          ...headers,
          'Authorization': 'Bearer $token',
        };
        resp = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );
      }
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('getPostById $id: HTTP ${resp.statusCode}');
        }
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return PostModel.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('getPostById error: $e');
      return null;
    }
  }

  static Future<List<Recipe>> getFavorites() async {
    final resp = await http.get(
      _uri('/favorites'),
      headers: await authHeaders(),
    );
    _ensureSuccess(resp);
    final Map<String, dynamic> data = jsonDecode(resp.body);
    final list = (data['favorites'] as List<dynamic>?) ?? [];
    return list.map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> addFavorite(Recipe r) async {
    final resp = await http.post(
      _uri('/favorites'),
      headers: await authHeaders(),
      body: jsonEncode({'recipe': r.toJson()}),
    );
    _ensureSuccess(resp);
  }

  static Future<void> removeFavorite(int id) async {
    final resp = await http.delete(
      _uri('/favorites/$id'),
      headers: await authHeaders(),
    );
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
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final resp = await http.post(
      _uri('/community/$id/like'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    _ensureSuccess(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['likes'] as num?)?.toInt() ??
        (data['likes_count'] as num?)?.toInt() ??
        0;
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
    final token = await AuthService.getAccessTokenForApi();
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
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final root = _tryParseJsonObject(resp.body);
      if (root != null) {
        throw apiExceptionFromResponse(
          resp.statusCode,
          root,
          fallback: 'Не удалось загрузить видео',
        );
      }
      throw Exception('API error ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CommunityVideo.fromJson(data['video'] as Map<String, dynamic>);
  }

  static Map<String, dynamic>? _tryParseJsonObject(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static void _ensureSuccess(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final root = _tryParseJsonObject(resp.body);
      final detail = root?['detail'];
      // FastAPI / HTTPBearer: часто строка "Not authenticated" при 401/403.
      if (detail is String &&
          (resp.statusCode == 401 || resp.statusCode == 403)) {
        final d = detail.toLowerCase();
        if (d.contains('not authenticated') ||
            d.contains('could not validate credentials') ||
            d.contains('credentials')) {
          throw const HanLoginRequiredException('Войдите в аккаунт');
        }
      }
      if (detail is Map<String, dynamic>) {
        final code = detail['code'] as String?;
        final msg = (detail['message'] as String?) ?? '';
        if (code == 'HAN_MEAL_PLAN_COOLDOWN') {
          throw HanMealPlanCooldownException(
            msg.isNotEmpty ? msg : 'Следующий AI meal plan будет доступен позже',
          );
        }
        if (code == 'HAN_PLUS_REQUIRED' ||
            code == 'HAN_AI_REQUIRED' ||
            code == 'HAN_PRO_REQUIRED') {
          throw HanPlusRequiredException(
            msg.isNotEmpty ? msg : 'Требуется подписка H.A.N. AI или Pro',
          );
        }
        if (code == 'LOGIN_REQUIRED') {
          throw HanLoginRequiredException(
            msg.isNotEmpty ? msg : 'Войдите в аккаунт',
          );
        }
        if (code == 'AI_SCANS_EXHAUSTED') {
          throw AiScansExhaustedException(
            isPlus: detail['is_plus'] as bool? ?? false,
            message: msg.isNotEmpty ? msg : null,
          );
        }
        if (code == 'AI_SCAN_RESERVE_REQUIRED') {
          throw AiScanReserveRequiredException(
            msg.isNotEmpty ? msg : 'Сначала забронируйте AI scan',
          );
        }
        if (code == 'CONTENT_BLOCKED') {
          throw apiExceptionFromResponse(
            resp.statusCode,
            root!,
            fallback: 'Публикация не прошла модерацию',
          );
        }
      }
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

  /// GET /meal-plans/limits
  static Future<Map<String, dynamic>> getMealPlanLimits() async {
    final resp = await http.get(
      _uri('/meal-plans/limits'),
      headers: await authHeaders(),
    );
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// POST /meal-plans/generate
  static Future<Map<String, dynamic>> generateMealPlan({
    required int durationDays,
    required Map<String, dynamic> preferences,
    String? startDate,
    int? variationSeed,
  }) async {
    final resp = await http.post(
      _uri('/meal-plans/generate'),
      headers: await authHeaders(),
      body: jsonEncode({
        'duration_days': durationDays,
        'preferences': preferences,
        if (startDate != null) 'start_date': startDate,
        if (variationSeed != null) 'variation_seed': variationSeed,
      }),
    ).timeout(const Duration(seconds: 45));
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// POST /meal-plans/regenerate
  static Future<Map<String, dynamic>> regenerateMealPlan({
    required Map<String, dynamic> plan,
    required String scope,
    int dayIndex = 0,
    int mealIndex = 0,
    String? modifier,
    Map<String, dynamic>? preferences,
    int? variationSeed,
  }) async {
    final resp = await http.post(
      _uri('/meal-plans/regenerate'),
      headers: await authHeaders(),
      body: jsonEncode({
        'plan': plan,
        'scope': scope,
        'day_index': dayIndex,
        'meal_index': mealIndex,
        if (modifier != null) 'modifier': modifier,
        if (preferences != null) 'preferences': preferences,
        if (variationSeed != null) 'variation_seed': variationSeed,
      }),
    ).timeout(const Duration(seconds: 45));
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<void> logMealPlanShoppingApplied() async {
    try {
      await http.post(
        _uri('/meal-plans/shopping-list/apply'),
        headers: await authHeaders(),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getSavedMealPlanById(String planId) async {
    final resp = await http.get(
      _uri('/meal-plans/saved/$planId'),
      headers: await authHeaders(),
    );
    if (resp.statusCode == 404) return null;
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> listSavedMealPlans({int limit = 10}) async {
    final resp = await http.get(
      _uri('/meal-plans/saved', {'limit': '$limit'}),
      headers: await authHeaders(),
    );
    _ensureSuccess(resp);
    final res = jsonDecode(resp.body) as Map<String, dynamic>;
    final plans = res['plans'] as List<dynamic>? ?? [];
    return plans
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>?> getLatestMealPlan() async {
    final resp = await http.get(
      _uri('/meal-plans/saved/latest'),
      headers: await authHeaders(),
    );
    if (resp.statusCode == 404) return null;
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMealPlanAnalytics({int days = 30}) async {
    final resp = await http.get(
      _uri('/meal-plans/analytics', {'days': '$days'}),
      headers: await authHeaders(),
    );
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<void> logMealPlanApplyCalendar({
    required int mealsAdded,
    required int durationDays,
  }) async {
    try {
      await http.post(
        _uri('/meal-plans/apply-calendar'),
        headers: await authHeaders(),
        body: jsonEncode({
          'meals_added': mealsAdded,
          'duration_days': durationDays,
        }),
      );
    } catch (_) {}
  }
}
