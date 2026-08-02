import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';
import 'miniapp_models.dart';

class MiniAppsService {
  static Future<List<MiniAppItem>> fetchCatalog({
    String? query,
    String? category,
    bool onlyInstalled = false,
    String sort = 'default',
  }) async {
    final params = <String, String>{};
    final q = query?.trim() ?? '';
    if (q.isNotEmpty) params['q'] = q;
    final cat = category?.trim() ?? '';
    if (cat.isNotEmpty) params['category'] = cat;
    if (onlyInstalled) params['only_installed'] = 'true';
    final sortValue = sort.trim();
    if (sortValue.isNotEmpty && sortValue != 'default') {
      params['sort'] = sortValue;
    }
    final response = await http.get(
      ApiService.uri('/miniapps/catalog', params.isEmpty ? null : params),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(MiniAppItem.fromJson)
        .toList(growable: false);
  }

  static Future<List<MiniAppItem>> fetchMyMiniApps() async {
    final response = await http.get(
      ApiService.uri('/miniapps/my'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(MiniAppItem.fromJson)
        .toList(growable: false);
  }

  static Future<List<MiniAppItem>> fetchByBot(int botId) async {
    final response = await http.get(
      ApiService.uri('/miniapps/by-bot/$botId'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(MiniAppItem.fromJson)
        .toList(growable: false);
  }

  static Future<MiniAppItem> createMiniApp(MiniAppCreateRequest request) async {
    final response = await http.post(
      ApiService.uri('/miniapps'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode(request.toJson()),
    );
    ApiService.ensureSuccess(response);
    return MiniAppItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<MiniAppItem> updateMiniApp(
    int miniAppId,
    MiniAppUpdateRequest request,
  ) async {
    final response = await http.patch(
      ApiService.uri('/miniapps/$miniAppId'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode(request.toJson()),
    );
    ApiService.ensureSuccess(response);
    return MiniAppItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> deleteMiniApp(int miniAppId) async {
    final response = await http.delete(
      ApiService.uri('/miniapps/$miniAppId'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
  }

  static Future<void> installMiniApp(int miniAppId) async {
    final response = await http.post(
      ApiService.uri('/miniapps/$miniAppId/install'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
  }

  static Future<void> uninstallMiniApp(int miniAppId) async {
    final response = await http.delete(
      ApiService.uri('/miniapps/$miniAppId/install'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
  }

  static Future<MiniAppLaunchContext> getLaunchContext(
    int miniAppId, {
    int? conversationId,
    String? startParam,
  }) async {
    final response = await http.post(
      ApiService.uri('/miniapps/$miniAppId/launch-init-data'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        if (conversationId != null) 'conversation_id': conversationId,
        if (startParam != null && startParam.trim().isNotEmpty)
          'start_param': startParam.trim(),
      }),
    );
    ApiService.ensureSuccess(response);
    return MiniAppLaunchContext.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Telegram WebApp.sendData → bot webhook + chat message.
  static Future<void> sendWebAppData(
    int miniAppId, {
    required String data,
    int? conversationId,
    String? buttonText,
  }) async {
    final response = await http.post(
      ApiService.uri('/miniapps/$miniAppId/web-app-data'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'data': data,
        if (conversationId != null) 'conversation_id': conversationId,
        if (buttonText != null && buttonText.trim().isNotEmpty)
          'button_text': buttonText.trim(),
      }),
    );
    ApiService.ensureSuccess(response);
  }

  static Future<List<MiniAppItem>> fetchModerationQueue({
    String? status,
  }) async {
    final params = <String, String>{};
    final normalized = status?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      params['status'] = normalized;
    }
    final response = await http.get(
      ApiService.uri(
        '/miniapps/moderation/pending',
        params.isEmpty ? null : params,
      ),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(MiniAppItem.fromJson)
        .toList(growable: false);
  }

  static Future<MiniAppItem> moderateMiniApp({
    required int miniAppId,
    required String moderationStatus,
    String? moderationNote,
  }) async {
    final response = await http.post(
      ApiService.uri('/miniapps/$miniAppId/moderate'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'moderation_status': moderationStatus,
        if (moderationNote != null && moderationNote.trim().isNotEmpty)
          'moderation_note': moderationNote.trim(),
      }),
    );
    ApiService.ensureSuccess(response);
    return MiniAppItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
