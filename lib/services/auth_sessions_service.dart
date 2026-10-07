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

  factory AuthSessionInfo.fromJson(Map json) {
    final data = Map<String, dynamic>.from(json);
    return AuthSessionInfo(
      id: _sessionJsonInt(data['id']),
      isCurrent: data['is_current'] == true,
      createdAt: DateTime.tryParse(data['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt: DateTime.tryParse(data['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deviceName: data['device_name'] as String?,
      devicePlatform: data['device_platform'] as String?,
      ipAddress: data['ip_address'] as String?,
    );
  }

  String get title {
    final name = deviceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final platform = devicePlatform?.trim();
    if (platform != null && platform.isNotEmpty) {
      switch (platform) {
        case 'web':
          return 'Браузер';
        case 'ios':
          return 'iPhone';
        case 'android':
          return 'Android';
        case 'macos':
          return 'Mac';
        default:
          return 'Устройство · $platform';
      }
    }
    return 'Браузер';
  }
}

int _sessionJsonInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

class AuthSessionsService {
  static String get _base => ServerConfig.apiBaseUrl;

  static List<AuthSessionInfo> parseSessionList(Object? raw) {
    Object? items = raw;
    if (raw is Map) items = raw['items'] ?? raw['sessions'];
    if (items is! List) return const [];
    final out = <AuthSessionInfo>[];
    for (final item in items) {
      if (item is! Map) continue;
      try {
        final session = AuthSessionInfo.fromJson(item);
        if (session.id > 0) out.add(session);
      } catch (_) {}
    }
    return out;
  }

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
    return parseSessionList(jsonDecode(response.body));
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
