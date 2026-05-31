import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'server_config.dart';

/// Лёгкие клиентские события (ai_scan paywall, открытие экранов и т.д.).
class ProductAnalytics {
  static String get _baseUrl => ServerConfig.apiBaseUrl;

  static Future<void> logEvent({
    required String eventType,
    String entityType = 'app',
    int entityId = 0,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final token = await AuthService.getAccessTokenForApi();
      if (token == null) return;

      final uri = Uri.parse('$_baseUrl/analytics/events');
      await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'event_type': eventType,
          'entity_type': entityType,
          'entity_id': entityId,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProductAnalytics.logEvent($eventType): $e');
      }
    }
  }
}
