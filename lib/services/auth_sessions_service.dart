import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class AuthSessionInfo {
  const AuthSessionInfo({
    required this.id,
    required this.isCurrent,
    required this.createdAt,
    required this.lastSeenAt,
    this.deviceName,
    this.devicePlatform,
    this.ipAddress,
  });

  final int id;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final String? deviceName;
  final String? devicePlatform;
  final String? ipAddress;

  factory AuthSessionInfo.fromJson(Map<String, dynamic> json) {
    return AuthSessionInfo(
      id: json['id'] as int,
      isCurrent: json['is_current'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deviceName: json['device_name'] as String?,
      devicePlatform: json['device_platform'] as String?,
      ipAddress: json['ip_address'] as String?,
    );
  }

  String get title {
    final name = deviceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final platform = devicePlatform?.trim();
    if (platform != null && platform.isNotEmpty) return 'Устройство · $platform';
    return 'Устройство #$id';
  }
}

class AuthSessionsService {
  static String get _base => ServerConfig.apiBaseUrl;

  static Future<List<AuthSessionInfo>> listSessions() async {
    final uri = Uri.parse('$_base/auth/sessions');
    final headers = await AuthService.authSessionHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить сеансы',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(AuthSessionInfo.fromJson)
        .toList();
  }

  static Future<void> revokeSession(int sessionId) async {
    final uri = Uri.parse('$_base/auth/sessions/$sessionId');
    final headers = await AuthService.authSessionHeaders();
    final response = await http.delete(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось завершить сеанс',
      );
    }
  }

  static Future<void> revokeOthers() async {
    final uri = Uri.parse('$_base/auth/sessions/revoke-others');
    final headers = await AuthService.authSessionHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http.post(uri, headers: headers, body: '{}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось завершить другие сеансы',
      );
    }
  }

  static Future<void> revokeAll() async {
    final uri = Uri.parse('$_base/auth/sessions/revoke-all');
    final headers = await AuthService.authSessionHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http.post(uri, headers: headers, body: '{}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось завершить все сеансы',
      );
    }
  }
}
