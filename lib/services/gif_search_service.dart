import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import '../models/gif_models.dart';
import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'server_config.dart';

class GifSearchService {
  static String get _base => ServerConfig.apiBaseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) {
      throw const ApiClientException(message: 'Необходим вход в аккаунт');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Never _throwError(http.Response response, String fallback) {
    final error = apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
    if (error.code == 'HAN_FEATURE_REQUIRED') {
      throw HanPlusRequiredException(
        error.message.isNotEmpty
            ? error.message
            : 'Требуется подписка с этой функцией',
      );
    }
    throw error;
  }

  static Future<GifCatalogPage> _getPage(
    Uri uri,
    String fallback,
  ) async {
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, fallback);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return GifCatalogPage.fromJson(body);
  }

  static Future<GifCatalogPage> search({
    required String query,
    int limit = 24,
    String? pos,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const GifCatalogPage(configured: true, items: []);
    }
    final uri = Uri.parse('$_base/gifs/search').replace(
      queryParameters: {
        'q': q,
        'limit': '$limit',
        if (pos != null && pos.isNotEmpty) 'pos': pos,
      },
    );
    return _getPage(uri, 'Не удалось найти GIF');
  }

  static Future<GifCatalogPage> featured({
    int limit = 24,
    String? pos,
  }) async {
    final uri = Uri.parse('$_base/gifs/featured').replace(
      queryParameters: {
        'limit': '$limit',
        if (pos != null && pos.isNotEmpty) 'pos': pos,
      },
    );
    return _getPage(uri, 'Не удалось загрузить GIF');
  }

  static Future<List<GifCatalogItem>> listFavorites() async {
    final uri = Uri.parse('$_base/gifs/favorites');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось загрузить избранные GIF');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = body['items'] as List<dynamic>? ?? const [];
    return raw.whereType<Map<String, dynamic>>().map((item) {
      final url = (item['media_url'] as String?)?.trim() ??
          (item['url'] as String?)?.trim() ??
          '';
      final preview = (item['preview_url'] as String?)?.trim() ?? url;
      return GifCatalogItem(
        id: '${item['id'] ?? url}',
        previewUrl: preview,
        url: url,
        title: item['title'] as String? ?? '',
      );
    }).where((e) => e.url.isNotEmpty).toList();
  }

  static Future<bool> toggleFavorite({
    required String mediaUrl,
    String? previewUrl,
    String? title,
  }) async {
    final uri = Uri.parse('$_base/gifs/favorites/toggle');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'media_url': mediaUrl.trim(),
          if (previewUrl != null && previewUrl.trim().isNotEmpty)
            'preview_url': previewUrl.trim(),
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось обновить избранные GIF');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['favorited'] as bool? ?? false;
  }
}
