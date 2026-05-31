import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'package:flutter/foundation.dart';

class AuthorSubscriptionService {
  static Future<bool> subscribe(String subscriber, String author) async {
    try {
      final uri = ApiService.uri('/authors/$author/subscribe');
      final body = {'subscriber': subscriber};
      final resp = await http.post(
        uri,
        headers: ApiService.jsonHeaders,
        body: jsonEncode(body),
      );
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['subscribed'] as bool? ?? false;
    } catch (e) {
      debugPrint('Error subscribing: $e');
      return false;
    }
  }

  static Future<bool> unsubscribe(String subscriber, String author) async {
    try {
      final uri = ApiService.uri('/authors/$author/subscribe', {'subscriber': subscriber});
      final resp = await http.delete(uri, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return !(data['subscribed'] as bool? ?? true);
    } catch (e) {
      debugPrint('Error unsubscribing: $e');
      return false;
    }
  }

  static Future<bool> isSubscribed(String subscriber, String author) async {
    try {
      final uri = ApiService.uri('/subscribers/$subscriber/is_subscribed/$author');
      final resp = await http.get(uri, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['subscribed'] as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking subscription: $e');
      return false;
    }
  }

  static Future<List<String>> getSubscriptions(String subscriber) async {
    try {
      final uri = ApiService.uri('/subscribers/$subscriber/subscriptions');
      final resp = await http.get(uri, headers: ApiService.jsonHeaders);
      ApiService.ensureSuccess(resp);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final subscriptions = data['subscriptions'] as List<dynamic>? ?? [];
      return subscriptions.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error fetching subscriptions: $e');
      return [];
    }
  }
}

