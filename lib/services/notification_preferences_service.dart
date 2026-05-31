// Сервис для работы с настройками уведомлений через backend API
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'server_config.dart';

String _parseErrorDetail(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final d = decoded['detail'];
      if (d is String && d.isNotEmpty) return d;
      if (d is List && d.isNotEmpty) {
        final first = d.first;
        if (first is Map<String, dynamic>) {
          final msg = first['msg'];
          final loc = first['loc'];
          final field = loc is List && loc.isNotEmpty ? loc.last.toString() : 'field';
          if (msg is String && msg.isNotEmpty) return '$field: $msg';
        }
      }
    }
  } catch (_) {}
  final trimmed = body.trim();
  if (trimmed.length > 280) return '${trimmed.substring(0, 280)}…';
  return trimmed.isEmpty ? 'Ошибка сервера' : trimmed;
}

bool _bool(dynamic v, [bool fallback = true]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

class NotificationPreferencesService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Получить настройки уведомлений текущего пользователя
  static Future<NotificationPreferences> getPreferences() async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/users/me/notification-preferences');
    var response = await http.get(uri, headers: _headers(token));

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.get(uri, headers: _headers(token));
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return NotificationPreferences.fromJson(data);
    }
    throw Exception(
      '${_parseErrorDetail(response.body)} (${response.statusCode})',
    );
  }

  /// Обновить настройки уведомлений
  static Future<NotificationPreferences> updatePreferences({
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? followsEnabled,
    bool? repostsEnabled,
    bool? mentionsEnabled,
    bool? systemEnabled,
    bool? pushEnabled,
  }) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/users/me/notification-preferences');
    final body = <String, dynamic>{};
    if (likesEnabled != null) body['likes_enabled'] = likesEnabled;
    if (commentsEnabled != null) body['comments_enabled'] = commentsEnabled;
    if (followsEnabled != null) body['follows_enabled'] = followsEnabled;
    if (repostsEnabled != null) body['reposts_enabled'] = repostsEnabled;
    if (mentionsEnabled != null) body['mentions_enabled'] = mentionsEnabled;
    if (systemEnabled != null) body['system_enabled'] = systemEnabled;
    if (pushEnabled != null) body['push_enabled'] = pushEnabled;

    var response = await http.patch(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.patch(
        uri,
        headers: _headers(token),
        body: jsonEncode(body),
      );
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return NotificationPreferences.fromJson(data);
    }
    throw Exception(
      '${_parseErrorDetail(response.body)} (${response.statusCode})',
    );
  }
}

class NotificationPreferences {
  final bool likesEnabled;
  final bool commentsEnabled;
  final bool followsEnabled;
  final bool repostsEnabled;
  final bool mentionsEnabled;
  final bool systemEnabled;
  final bool pushEnabled;

  NotificationPreferences({
    required this.likesEnabled,
    required this.commentsEnabled,
    required this.followsEnabled,
    required this.repostsEnabled,
    required this.mentionsEnabled,
    required this.systemEnabled,
    required this.pushEnabled,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      likesEnabled: _bool(json['likes_enabled']),
      commentsEnabled: _bool(json['comments_enabled']),
      followsEnabled: _bool(json['follows_enabled']),
      repostsEnabled: _bool(json['reposts_enabled']),
      mentionsEnabled: _bool(json['mentions_enabled']),
      systemEnabled: _bool(json['system_enabled']),
      pushEnabled: _bool(json['push_enabled']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'likes_enabled': likesEnabled,
      'comments_enabled': commentsEnabled,
      'follows_enabled': followsEnabled,
      'reposts_enabled': repostsEnabled,
      'mentions_enabled': mentionsEnabled,
      'system_enabled': systemEnabled,
      'push_enabled': pushEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? followsEnabled,
    bool? repostsEnabled,
    bool? mentionsEnabled,
    bool? systemEnabled,
    bool? pushEnabled,
  }) {
    return NotificationPreferences(
      likesEnabled: likesEnabled ?? this.likesEnabled,
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
      followsEnabled: followsEnabled ?? this.followsEnabled,
      repostsEnabled: repostsEnabled ?? this.repostsEnabled,
      mentionsEnabled: mentionsEnabled ?? this.mentionsEnabled,
      systemEnabled: systemEnabled ?? this.systemEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
    );
  }
}
