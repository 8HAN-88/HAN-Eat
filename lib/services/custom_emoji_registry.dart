import 'dart:convert';

import '../core/network/haneat_http_client.dart';
import '../models/emoji_pack_models.dart';
import 'auth_service.dart';
import 'server_config.dart';

/// In-memory map of custom emoji id → media URL for inline render.
class CustomEmojiRegistry {
  CustomEmojiRegistry._();
  static final CustomEmojiRegistry instance = CustomEmojiRegistry._();

  final Map<int, String> _urls = {};
  final Map<int, String> _shortcodes = {};
  final Set<int> _inflight = {};

  String? urlFor(int id) => _urls[id];

  String? shortcodeFor(int id) => _shortcodes[id];

  void remember(CustomEmojiItem item) {
    if (item.id <= 0 || item.mediaUrl.trim().isEmpty) return;
    _urls[item.id] = item.mediaUrl;
    if ((item.shortcode ?? '').trim().isNotEmpty) {
      _shortcodes[item.id] = item.shortcode!.trim();
    }
  }

  void rememberPacks(Iterable<EmojiPack> packs) {
    for (final pack in packs) {
      for (final item in pack.items) {
        remember(item);
      }
    }
  }

  Future<void> resolveMissing(Iterable<int> ids) async {
    final need = ids
        .where((id) => id > 0 && !_urls.containsKey(id) && !_inflight.contains(id))
        .toSet()
        .take(80)
        .toList();
    if (need.isEmpty) return;
    _inflight.addAll(need);
    try {
      final token = await AuthService.getAccessTokenForApi();
      if (token == null || token.isEmpty) return;
      final uri = Uri.parse(
        '${ServerConfig.apiBaseUrl}/emoji/resolve?ids=${need.join(',')}',
      );
      final response = await HanEatHttpClient.withShared(
        (client) => client.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = body['items'] as List<dynamic>? ?? const [];
      for (final row in raw.whereType<Map<String, dynamic>>()) {
        remember(CustomEmojiItem.fromJson(row));
      }
    } catch (_) {
      // Render fallback stays as a placeholder; next paint can retry.
    } finally {
      _inflight.removeAll(need);
    }
  }
}

final _tokenRe = RegExp(r'\[\[e:(\d+)\]\]');
final _reactionRe = RegExp(r'^ce:(\d+)$');

int? parseCustomEmojiTokenId(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final reaction = _reactionRe.firstMatch(text);
  if (reaction != null) return int.tryParse(reaction.group(1)!);
  final token = _tokenRe.firstMatch(text);
  if (token != null) return int.tryParse(token.group(1)!);
  return null;
}

List<int> parseCustomEmojiIds(String? text) {
  final ids = <int>[];
  for (final match in _tokenRe.allMatches(text ?? '')) {
    final id = int.tryParse(match.group(1) ?? '');
    if (id != null && id > 0) ids.add(id);
  }
  return ids;
}

String customEmojiToken(int id) => '[[e:$id]]';

String customEmojiReaction(int id) => 'ce:$id';

String previewTextWithCustomEmoji(String text) {
  final replaced = text.replaceAllMapped(_tokenRe, (match) {
    final id = int.tryParse(match.group(1) ?? '') ?? 0;
    final short = CustomEmojiRegistry.instance.shortcodeFor(id);
    if (short != null && short.isNotEmpty) return ':$short:';
    return '✦';
  });
  final clean = replaced.trim();
  return clean.isEmpty ? 'Сообщение' : clean;
}

/// Truncate by visual glyphs so `[[e:123]]` is one character and is never split.
String truncateKeepingCustomEmojiTokens(String text, int maxVisualChars) {
  if (text.isEmpty || maxVisualChars <= 0) return text;
  var visual = 0;
  var index = 0;
  while (index < text.length && visual < maxVisualChars) {
    final match = _tokenRe.matchAsPrefix(text, index);
    if (match != null) {
      visual += 1;
      index = match.end;
      continue;
    }
    visual += 1;
    index += 1;
  }
  if (index >= text.length) return text;
  return '${text.substring(0, index).trimRight()}…';
}
