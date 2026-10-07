import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class TotpSetupInfo {
  const TotpSetupInfo({
    required this.secret,
    required this.otpauthUri,
    required this.issuer,
  });

  final String secret;
  final String otpauthUri;
  final String issuer;

  factory TotpSetupInfo.fromJson(Map json) {
    final data = Map<String, dynamic>.from(json);
    return TotpSetupInfo(
      secret: data['secret'] as String? ?? '',
      otpauthUri: data['otpauth_uri'] as String? ?? '',
      issuer: data['issuer'] as String? ?? 'HanWe',
    );
  }
}

Map<String, dynamic>? _totpJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

/// Client for /auth/2fa/* enrollment endpoints (authenticated).
class TotpAuthService {
  static String get _base => ServerConfig.apiBaseUrl;

  static Future<Map<String, String>> _headers() async {
    final headers = await AuthService.authSessionHeaders();
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  static Future<bool> status() async {
    final response = await http.get(
      Uri.parse('$_base/auth/2fa/status'),
      headers: await _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось проверить 2FA',
      );
    }
    return parseStatus(jsonDecode(response.body));
  }

  static bool parseStatus(Object? raw) {
    final data = _totpJsonMap(raw);
    if (data == null) return false;
    final enabled = data['enabled'];
    if (enabled is bool) return enabled;
    if (enabled is num) return enabled != 0;
    if (enabled is String) {
      final t = enabled.trim().toLowerCase();
      return t == 'true' || t == '1' || t == 'yes';
    }
    return false;
  }

  static TotpSetupInfo parseSetup(Object? raw) {
    final data = _totpJsonMap(raw);
    if (data == null) {
      throw const FormatException('TotpSetupInfo: invalid payload');
    }
    return TotpSetupInfo.fromJson(data);
  }

  static Future<TotpSetupInfo> setup() async {
    final response = await http.post(
      Uri.parse('$_base/auth/2fa/setup'),
      headers: await _headers(),
      body: '{}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось начать настройку 2FA',
      );
    }
    return parseSetup(jsonDecode(response.body));
  }

  static Future<void> enable({required String code}) async {
    final response = await http.post(
      Uri.parse('$_base/auth/2fa/enable'),
      headers: await _headers(),
      body: jsonEncode({'code': code.trim()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Неверный код. Попробуйте ещё раз.',
      );
    }
  }

  static Future<void> disable({
    required String password,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/auth/2fa/disable'),
      headers: await _headers(),
      body: jsonEncode({
        'password': password,
        'code': code.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось отключить 2FA',
      );
    }
  }
}
