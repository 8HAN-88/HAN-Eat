import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/legal_urls.dart';
import 'auth_service.dart';
import 'server_config.dart';

class LegalStatus {
  LegalStatus({
    required this.version,
    required this.privacyUrl,
    required this.termsUrl,
    required this.consentText,
  });

  final String version;
  final String privacyUrl;
  final String termsUrl;
  final String consentText;

  factory LegalStatus.fromJson(Map<String, dynamic> json) {
    return LegalStatus(
      version: json['version'] as String? ?? '',
      privacyUrl: json['privacy_url'] as String? ?? LegalUrls.privacyPolicy,
      termsUrl: json['terms_url'] as String? ?? LegalUrls.termsOfService,
      consentText: json['consent_text'] as String? ?? '',
    );
  }
}

/// Юридические документы и фиксация согласия на API.
class LegalService {
  static String get _base => '${ServerConfig.apiBaseUrl}/legal';

  /// Локальный fallback, если `/legal/status` недоступен (старый API).
  static LegalStatus fallbackStatus() {
    return LegalStatus(
      version: '2026-06-03',
      privacyUrl: LegalUrls.privacyPolicy,
      termsUrl: LegalUrls.termsOfService,
      consentText:
          'Я подтверждаю, что ознакомился(ась) с Политикой конфиденциальности '
          'и Пользовательским соглашением, даю согласие на обработку персональных '
          'данных в соответствии с Федеральным законом № 152-ФЗ.',
    );
  }

  static Future<LegalStatus> fetchStatus() async {
    final uri = Uri.parse('$_base/status');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Не удалось загрузить юридические документы');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return LegalStatus.fromJson(data);
  }

  /// Статус с API или fallback без блокировки экрана.
  static Future<LegalStatus> fetchStatusResilient() async {
    try {
      return await fetchStatus();
    } catch (_) {
      return fallbackStatus();
    }
  }

  static Future<void> acceptConsent() async {
    final token = await AuthService.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Требуется авторизация');
    }
    final uri = Uri.parse('$_base/accept');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'accept_legal': true}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Не удалось сохранить согласие');
    }

    final user = AuthService.instance.currentUser;
    if (user != null) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final updated = user.copyWith(
        legalConsentRequired: false,
        legalConsentVersion: data['legal_consent_version'] as String?,
      );
      await AuthService.instance.updateStoredUser(updated);
    }
  }
}
