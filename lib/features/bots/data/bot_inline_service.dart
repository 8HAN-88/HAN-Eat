import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../services/api_service.dart';

/// Модель результата inline
class InlineResult {
  final String id;
  final String type; // command, miniapp, etc.
  final String title;
  final String description;
  final String payload; // что отправить в чат
  final int? miniAppId;
  final String? miniAppShortName;

  InlineResult({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.payload,
    this.miniAppId,
    this.miniAppShortName,
  });

  factory InlineResult.fromJson(Map<String, dynamic> json) => InlineResult(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        payload: json['payload'] as String,
        miniAppId: (json['miniapp_id'] as num?)?.toInt(),
        miniAppShortName: json['miniapp_short_name'] as String?,
      );
}

/// Сервис для Inline Mode (@bot query)
class BotInlineService {
  static Future<List<InlineResult>> getInlineResults({
    required String botUsername,
    String query = '',
    int limit = 8,
  }) async {
    try {
      final uri = ApiService.uri('/bots/inline', {
        'bot': botUsername,
        'query': query,
        'limit': '$limit',
      });
      final headers = await ApiService.authHeaders();
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['results'] as List?) ?? [];
        return list.map((e) => InlineResult.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }
}
