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
}
