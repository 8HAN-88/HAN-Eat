import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class CloseFriendUser {
  const CloseFriendUser({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;

  factory CloseFriendUser.fromJson(Map<String, dynamic> json) {
    return CloseFriendUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'User',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  String get subtitle {
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return '@$u';
    return 'ID $id';
  }
}

class CloseFriendsService {
  static String get _base => ServerConfig.apiBaseUrl;

  static Future<List<CloseFriendUser>> list() async {
    final headers = await AuthService.authSessionHeaders();
    final response = await http.get(
      Uri.parse('$_base/users/me/close-friends'),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить близких друзей',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CloseFriendUser.fromJson)
        .toList();
  }

  static Future<void> add(int userId) async {
    final headers = await AuthService.authSessionHeaders();
    final response = await http.post(
      Uri.parse('$_base/users/me/close-friends/$userId'),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось добавить',
      );
    }
  }

  static Future<void> remove(int userId) async {
    final headers = await AuthService.authSessionHeaders();
    final response = await http.delete(
      Uri.parse('$_base/users/me/close-friends/$userId'),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось удалить',
      );
    }
  }
}
