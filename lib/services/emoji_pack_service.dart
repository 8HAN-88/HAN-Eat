import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import '../models/emoji_pack_models.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'custom_emoji_registry.dart';
import 'server_config.dart';

class EmojiPackService {
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

  static List<EmojiPack> _parsePacks(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось загрузить эмодзи-паки');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawItems = body['items'] as List<dynamic>? ?? const [];
    final packs = rawItems
        .whereType<Map<String, dynamic>>()
        .map(EmojiPack.fromJson)
        .toList();
    CustomEmojiRegistry.instance.rememberPacks(packs);
    return packs;
  }

  static EmojiPack _parsePack(http.Response response, String fallback) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, fallback);
    }
    final pack = EmojiPack.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    CustomEmojiRegistry.instance.rememberPacks([pack]);
    return pack;
  }

  static Future<List<EmojiPack>> listMyPacks() async {
    final uri = Uri.parse('$_base/emoji/my');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePacks(response);
  }

  static Future<List<EmojiPack>> listCatalog({
    String query = '',
    int limit = 60,
  }) async {
    final q = query.trim();
    final uri = Uri.parse(
      '$_base/emoji/catalog?q=${Uri.encodeQueryComponent(q)}&limit=$limit',
    );
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePacks(response);
  }

  static Future<EmojiPack> getPackBySlug(String slug) async {
    final clean = slug.trim();
    final uri = Uri.parse('$_base/emoji/by-slug/$clean');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePack(response, 'Не удалось открыть эмодзи-пак');
  }

  static Future<void> importBySlug(String slug) async {
    final clean = slug.trim();
    final uri = Uri.parse('$_base/emoji/import/$clean');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось установить эмодзи-пак');
    }
  }

  static Future<List<EmojiPack>> listMarketplace({
    String query = '',
    int limit = 60,
  }) async {
    final q = query.trim();
    final uri = Uri.parse(
      '$_base/emoji/marketplace?q=${Uri.encodeQueryComponent(q)}&limit=$limit',
    );
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePacks(response);
  }

  static Future<EmojiPack> getPack(int packId) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.get(uri, headers: headers),
    );
    return _parsePack(response, 'Не удалось загрузить эмодзи-пак');
  }

  static Future<EmojiPack> createPack({
    required String title,
    bool isPublic = true,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs');
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
    return _parsePack(response, 'Не удалось создать эмодзи-пак');
  }

  static Future<EmojiPack> updatePack({
    required int packId,
    String? title,
    bool? isPublic,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId');
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
    return _parsePack(response, 'Не удалось обновить эмодзи-пак');
  }

  static Future<void> reorderEmojis({
    required int packId,
    required List<int> emojiIds,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/items/reorder');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({'emoji_ids': emojiIds}),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось изменить порядок');
    }
  }

  static Future<EmojiPack> addEmoji({
    required int packId,
    required String mediaUrl,
    String? shortcode,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/items');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'media_url': mediaUrl,
          if (shortcode != null && shortcode.trim().isNotEmpty)
            'shortcode': shortcode.trim(),
        }),
      ),
    );
    return _parsePack(response, 'Не удалось добавить эмодзи');
  }

  static Future<void> deleteEmoji({
    required int packId,
    required int emojiId,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/items/$emojiId');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.delete(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось удалить эмодзи');
    }
  }

  static Future<EmojiPack> listPackForSale({
    required int packId,
    required int priceStars,
  }) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/list');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(
        uri,
        headers: headers,
        body: jsonEncode({'price_stars': priceStars}),
      ),
    );
    return _parsePack(response, 'Не удалось выставить пак');
  }

  static Future<Map<String, dynamic>> buyPack(int packId) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/buy');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось купить эмодзи-пак');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> installPack(int packId) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/install');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.post(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось установить эмодзи-пак');
    }
  }

  static Future<void> uninstallPack(int packId) async {
    final uri = Uri.parse('$_base/emoji/packs/$packId/install');
    final headers = await _headers();
    final response = await HanEatHttpClient.withShared(
      (client) => client.delete(uri, headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwError(response, 'Не удалось удалить эмодзи-пак');
    }
  }

  static Future<void> resolveIds(Iterable<int> ids) async {
    await CustomEmojiRegistry.instance.resolveMissing(ids);
  }
}
