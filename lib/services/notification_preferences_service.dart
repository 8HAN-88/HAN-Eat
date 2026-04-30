/// Сервис для работы с настройками уведомлений через backend API
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class NotificationPreferencesService {
  static const String baseUrl = 'http://localhost:5000/api/v1';

  /// Получить настройки уведомлений текущего пользователя
  static Future<NotificationPreferences> getPreferences() async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/users/me/notification-preferences');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return NotificationPreferences.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to load notification preferences');
    }
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
    final token = await AuthService.getAccessToken();
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

    final response = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return NotificationPreferences.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to update notification preferences');
    }
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
      likesEnabled: json['likes_enabled'] as bool? ?? true,
      commentsEnabled: json['comments_enabled'] as bool? ?? true,
      followsEnabled: json['follows_enabled'] as bool? ?? true,
      repostsEnabled: json['reposts_enabled'] as bool? ?? true,
      mentionsEnabled: json['mentions_enabled'] as bool? ?? true,
      systemEnabled: json['system_enabled'] as bool? ?? true,
      pushEnabled: json['push_enabled'] as bool? ?? true,
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

