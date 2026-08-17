import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/community_video.dart';
import '../models/post_model.dart';

import '../features/bots/data/bot_models.dart';
import '../features/monetization/data/donation_models.dart';
import '../core/network/haneat_http_client.dart';
import 'server_config.dart';
import 'auth_service.dart';
import '../utils/api_error_parser.dart';

/// Бэкенд вернул 403: нужна подписка с AI (HanWe AI или Pro).
/// Алиас для совместимости: раньше «Plus», сейчас AI/Pro.
typedef HanAiRequiredException = HanPlusRequiredException;

class HanPlusRequiredException implements Exception {
  const HanPlusRequiredException(
      [this.message = 'Требуется подписка с этой функцией']);
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
    return Uri.parse('$_effectiveBaseUrl$fullPath')
        .replace(queryParameters: query);
  }

  // Публичные методы для использования в других сервисах
  static Uri uri(String path, [Map<String, dynamic>? query]) =>
      _uri(path, query);
  static Map<String, String> get jsonHeaders => _jsonHeaders;

  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  static Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
  }

  static Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers, body: body),
    );
  }

  static Future<http.Response> _delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return HanEatHttpClient.withShared(
      (client) => client.delete(uri, headers: headers, body: body),
    );
  }

  static Future<http.Response> _patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return HanEatHttpClient.withShared(
      (client) => client.patch(uri, headers: headers, body: body),
    );
  }

  static Future<Map<String, String>> authHeaders() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) return _jsonHeaders;
    return {
      ..._jsonHeaders,
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> fetchSettings() async {
    final resp = await _get(_uri('/settings'));
    _ensureSuccess(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<void> updateSettings({String? language}) async {
    final payload = <String, dynamic>{};
    if (language != null) payload['language'] = language;
    final resp = await _post(
      _uri('/settings'),
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    _ensureSuccess(resp);
  }


  /// Получить пост по ID (для deep-link haneat://post/:id).
  static Future<PostModel?> getPostById(int id) async {
    try {
      final uri = _uri('/posts/$id');
      var headers = await authHeaders();
      var resp = await _get(uri, headers: headers).timeout(
        const Duration(seconds: 15),
      );
      if (resp.statusCode == 401) {
        final token = await AuthService.refreshToken();
        headers = {
          ...headers,
          'Authorization': 'Bearer $token',
        };
        resp = await _get(uri, headers: headers).timeout(
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






  static Future<List<CommunityVideo>> fetchCommunityVideos(
      {String? tag}) async {
    try {
      final query = <String, String>{};
      if (tag != null && tag.isNotEmpty) {
        query['tag'] = tag;
      }
      final resp = await _get(_uri('/community', query))
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
    final resp = await _post(
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
    String? videoUrl,
    String? thumbnailUrl,
    String? avatar,
    int? channelId,
  }) async {
    if (videoUrl == null || videoUrl.trim().isEmpty) {
      throw Exception('Не удалось получить URL загруженного видео');
    }
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт, чтобы загрузить видео');
    }
    final headers = <String, String>{
      ..._jsonHeaders,
      'Authorization': 'Bearer $token',
    };
    final resp = await _post(
      _uri('/community'),
      headers: headers,
      body: jsonEncode({
        'title': title,
        'author': author,
        'description': description,
        'tags': tags,
        'video_url': videoUrl,
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
          'thumbnail_url': thumbnailUrl,
        'avatar': avatar,
        'status': 'pending',
        if (channelId != null) 'channel_id': channelId,
      }),
    ).timeout(const Duration(minutes: 2), onTimeout: () {
      throw TimeoutException('Превышено время ожидания ответа от сервера');
    });
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
        if (code == 'HAN_PLUS_REQUIRED' ||
            code == 'HAN_AI_REQUIRED' ||
            code == 'HAN_PRO_REQUIRED' ||
            code == 'HAN_CREATOR_REQUIRED' ||
            code == 'HAN_FEATURE_REQUIRED') {
          throw HanPlusRequiredException(
            msg.isNotEmpty ? msg : 'Требуется подписка с этой функцией',
          );
        }
        if (code == 'LOGIN_REQUIRED') {
          throw HanLoginRequiredException(
            msg.isNotEmpty ? msg : 'Войдите в аккаунт',
          );
        }
        if (code == 'CONTENT_BLOCKED') {
          throw apiExceptionFromResponse(
            resp.statusCode,
            root!,
            fallback: 'Публикация не прошла модерацию',
          );
        }
        // Stars / generic structured FastAPI errors (incl. 402 STARS_REQUIRED).
        throw apiExceptionFromResponse(
          resp.statusCode,
          root!,
          fallback: 'Произошла ошибка',
        );
      }
      if (resp.statusCode == 402) {
        throw const ApiClientException(
          statusCode: 402,
          code: 'STARS_REQUIRED',
          message: 'Недостаточно звёзд',
        );
      }
      throw Exception('API error ${resp.statusCode}: ${resp.body}');
    }
  }

  // Публичный метод для использования в других сервисах
  static void ensureSuccess(http.Response resp) => _ensureSuccess(resp);



  static Future<BotResponse> createBot(BotCreateRequest request) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/create'),
      headers: headers,
      body: jsonEncode(request.toJson()),
    );
    _ensureSuccess(response);
    return BotResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<BotListItem>> getMyBots() async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/bots/my'),
      headers: headers,
    );
    _ensureSuccess(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => BotListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<BotResponse> getBot(int botId) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/bots/$botId'),
      headers: headers,
    );
    _ensureSuccess(response);
    return BotResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<BotResponse> updateBot(
    int botId,
    BotUpdateRequest request,
  ) async {
    final headers = await authHeaders();
    final response = await _patch(
      _uri('/bots/$botId'),
      headers: headers,
      body: jsonEncode(request.toJson()),
    );
    _ensureSuccess(response);
    return BotResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<BotResponse> revokeBotToken(int botId) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/$botId/token/revoke'),
      headers: headers,
      body: '{}',
    );
    _ensureSuccess(response);
    return BotResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> deleteBot(int botId) async {
    final headers = await authHeaders();
    final response = await _delete(
      _uri('/bots/$botId'),
      headers: headers,
    );
    _ensureSuccess(response);
  }

  static Future<List<BotCommandCreate>> getBotCommands(int botId) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/bots/$botId/commands'),
      headers: headers,
    );
    _ensureSuccess(response);
    final list = jsonDecode(response.body) as List;
    return list.map((e) {
      final item = e as Map<String, dynamic>;
      final rowsRaw = item['inline_button_rows'] as List? ?? const [];
      final rows = <List<BotInlineButton>>[];
      for (final row in rowsRaw) {
        if (row is! List) continue;
        final parsed = row
            .whereType<Map<String, dynamic>>()
            .map(BotInlineButton.fromJson)
            .where((b) => b.text.trim().isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) rows.add(parsed);
      }
      if (rows.isEmpty) {
        final flat = ((item['inline_buttons'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BotInlineButton.fromJson)
            .where((b) => b.text.trim().isNotEmpty)
            .toList();
        if (flat.isNotEmpty) rows.add(flat);
      }
      final replyRowsRaw = item['reply_button_rows'] as List? ?? const [];
      final replyRows = <List<String>>[];
      for (final row in replyRowsRaw) {
        if (row is! List) continue;
        final parsed = <String>[];
        for (final btn in row) {
          if (btn is Map<String, dynamic>) {
            final t = (btn['text'] as String?)?.trim() ?? '';
            if (t.isNotEmpty) parsed.add(t);
          } else if (btn is String && btn.trim().isNotEmpty) {
            parsed.add(btn.trim());
          }
        }
        if (parsed.isNotEmpty) replyRows.add(parsed);
      }
      return BotCommandCreate(
        command: item['command'] as String,
        description: item['description'] as String,
        responseText: item['response_text'] as String?,
        inlineButtonRows: rows,
        replyButtonRows: replyRows,
        replyKeyboardOneTime:
            item['reply_keyboard_one_time'] as bool? ?? false,
        replyKeyboardResize: item['reply_keyboard_resize'] as bool? ?? true,
        replyKeyboardPlaceholder:
            item['reply_keyboard_placeholder'] as String?,
        removeReplyKeyboard: item['remove_reply_keyboard'] as bool? ?? false,
      );
    }).toList();
  }

  static Future<void> addBotCommand(int botId, BotCommandCreate cmd) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/$botId/commands'),
      headers: headers,
      body: jsonEncode(cmd.toJson()),
    );
    _ensureSuccess(response);
  }

  static Future<void> updateBotCommand({
    required int botId,
    required String command,
    required BotCommandCreate cmd,
  }) async {
    final headers = await authHeaders();
    final response = await _patch(
      _uri('/bots/$botId/commands/$command'),
      headers: headers,
      body: jsonEncode({
        'description': cmd.description,
        'response_text': cmd.responseText,
        'inline_button_rows': cmd.inlineButtonRows
            .map((row) => row.map((b) => b.toJson()).toList())
            .toList(),
        'clear_inline_buttons': cmd.inlineButtonRows.isEmpty,
        'reply_button_rows': cmd.replyButtonRows
            .map((row) => row.map((text) => {'text': text}).toList())
            .toList(),
        'clear_reply_buttons': cmd.replyButtonRows.isEmpty,
        'reply_keyboard_one_time': cmd.replyKeyboardOneTime,
        'reply_keyboard_resize': cmd.replyKeyboardResize,
        'reply_keyboard_placeholder': cmd.replyKeyboardPlaceholder,
        'remove_reply_keyboard': cmd.removeReplyKeyboard,
      }),
    );
    _ensureSuccess(response);
  }

  static Future<void> deleteBotCommand(int botId, String command) async {
    final headers = await authHeaders();
    final response = await _delete(
      _uri('/bots/$botId/commands/$command'),
      headers: headers,
    );
    _ensureSuccess(response);
  }

  static Future<void> addBotToChat({
    required int botId,
    required int conversationId,
  }) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/$botId/add-to-chat'),
      headers: headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );
    _ensureSuccess(response);
  }

  static Future<void> setBotWebhook({
    required int botId,
    required String url,
    String? secretToken,
  }) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/$botId/webhook'),
      headers: headers,
      body: jsonEncode({
        'url': url,
        if (secretToken != null && secretToken.trim().isNotEmpty)
          'secret_token': secretToken.trim(),
      }),
    );
    _ensureSuccess(response);
  }

  static Future<void> deleteBotWebhook(int botId) async {
    final headers = await authHeaders();
    final response = await _delete(
      _uri('/bots/$botId/webhook'),
      headers: headers,
    );
    _ensureSuccess(response);
  }

  static Future<bool> testBotWebhook(int botId) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/bots/$botId/webhook/test'),
      headers: headers,
    );
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['delivered'] == true;
  }

  static Future<BotAnalyticsResponse> getBotAnalytics({
    required int botId,
    int days = 30,
  }) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/bots/$botId/analytics', {'days': '$days'}),
      headers: headers,
    );
    _ensureSuccess(response);
    return BotAnalyticsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<BotWebhookAttempt>> getBotWebhookAttempts({
    required int botId,
    int limit = 30,
  }) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/bots/$botId/webhook/attempts', {'limit': '$limit'}),
      headers: headers,
    );
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BotWebhookAttempt.fromJson)
        .toList();
  }

  // === Donations ===

  static Future<Donation> createDonation(DonationCreateRequest request) async {
    final headers = await authHeaders();
    final response = await _post(
      _uri('/donations'),
      headers: headers,
      body: jsonEncode(request.toJson()),
    );
    _ensureSuccess(response);
    return Donation.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<Donation>> getReceivedDonations(
      {int limit = 50, int offset = 0}) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/donations/received', {'limit': '$limit', 'offset': '$offset'}),
      headers: headers,
    );
    _ensureSuccess(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => Donation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Donation>> getSentDonations(
      {int limit = 50, int offset = 0}) async {
    final headers = await authHeaders();
    final response = await _get(
      _uri('/donations/sent', {'limit': '$limit', 'offset': '$offset'}),
      headers: headers,
    );
    _ensureSuccess(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => Donation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
