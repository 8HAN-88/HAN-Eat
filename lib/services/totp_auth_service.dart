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

  factory TotpSetupInfo.fromJson(Map<String, dynamic> json) {
    return TotpSetupInfo(
      secret: json['secret'] as String? ?? '',
      otpauthUri: json['otpauth_uri'] as String? ?? '',
      issuer: json['issuer'] as String? ?? 'HanWe',
    );
  }
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
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['enabled'] as bool? ?? false;
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
    return TotpSetupInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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
