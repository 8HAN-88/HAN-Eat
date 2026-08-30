import 'dart:convert';

import '../core/network/haneat_http_client.dart';
import '../models/post_model.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class PostReactionService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static Future<List<PostReactionChip>> toggle({
    required int postId,
    required String emoji,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) {
      throw const ApiClientException(message: 'Войдите в аккаунт');
    }
    final uri = Uri.parse('$baseUrl/posts/$postId/reactions');
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'emoji': emoji}),
      ),
    );
    if (response.statusCode == 401) {
      final refreshed = await AuthService.refreshToken();
      final retry = await HanEatHttpClient.withShared(
        (client) => client.post(
          uri,
          headers: {
            'Authorization': 'Bearer $refreshed',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'emoji': emoji}),
        ),
      );
      if (retry.statusCode >= 200 && retry.statusCode < 300) {
        return _parse(retry.body);
      }
      throw apiExceptionFromResponse(
        retry.statusCode,
        jsonDecode(retry.body),
        fallback: 'Не удалось поставить реакцию',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parse(response.body);
    }
    throw apiExceptionFromResponse(
      response.statusCode,
      jsonDecode(response.body),
      fallback: 'Не удалось поставить реакцию',
    );
  }

  static List<PostReactionChip> _parse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['reactions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => PostReactionChip.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.emoji.isNotEmpty)
        .toList();
  }
}
