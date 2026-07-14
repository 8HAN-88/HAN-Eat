import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import '../models/sticker_models.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class StickerService {
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
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  static List<StickerPack> _parsePacks(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось загрузить стикеры');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawItems = body['items'] as List<dynamic>? ?? const [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(StickerPack.fromJson)
        .toList();
  }

  static Future<List<StickerPack>> listMyPacks() async {
    final uri = Uri.parse('$_base/stickers/my');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePacks(response);
  }

  static Future<StickerPack> createPack({
    required String title,
    bool isPublic = true,
  }) async {
    final uri = Uri.parse('$_base/stickers/packs');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'title': title,
          'is_public': isPublic,
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось создать стикерпак');
    }
    return StickerPack.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<StickerPack> addStickerToPack({
    required int packId,
    required String mediaUrl,
    String? emoji,
    String stickerType = 'static',
  }) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId/stickers');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'media_url': mediaUrl,
          if (emoji != null && emoji.trim().isNotEmpty) 'emoji': emoji.trim(),
          'sticker_type': stickerType,
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось добавить стикер');
    }
    return StickerPack.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> installPack(int packId) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId/install');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось установить стикерпак');
    }
  }

  static Future<void> uninstallPack(int packId) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId/install');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.delete(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось удалить стикерпак');
    }
  }

  static Future<List<StickerPack>> listCatalog({
    String query = '',
    int limit = 60,
  }) async {
    final q = query.trim();
    final uri = Uri.parse(
      '$_base/stickers/catalog?q=${Uri.encodeQueryComponent(q)}&limit=$limit',
    );
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePacks(response);
  }

  static Future<StickerPack> getPack(int packId) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось загрузить стикерпак');
    }
    return StickerPack.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<StickerPack> updatePack({
    required int packId,
    String? title,
    bool? isPublic,
  }) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.patch(
        uri,
        headers: headers,
        body: jsonEncode({
          if (title != null) 'title': title,
          if (isPublic != null) 'is_public': isPublic,
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось обновить стикерпак');
    }
    return StickerPack.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> deleteSticker({
    required int packId,
    required int stickerId,
  }) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId/stickers/$stickerId');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.delete(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось удалить стикер');
    }
  }

  static Future<void> reorderStickers({
    required int packId,
    required List<int> stickerIds,
  }) async {
    final uri = Uri.parse('$_base/stickers/packs/$packId/stickers/reorder');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({'sticker_ids': stickerIds}),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось сохранить порядок стикеров');
    }
  }

  static Future<StickerPack> getPackBySlug(String slug) async {
    final clean = slug.trim();
    final uri = Uri.parse('$_base/stickers/packs/slug/$clean');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось открыть стикерпак');
    }
    return StickerPack.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> importBySlug(String slug) async {
    final clean = slug.trim();
    final uri = Uri.parse('$_base/stickers/import/$clean');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось импортировать стикерпак');
    }
  }
}
