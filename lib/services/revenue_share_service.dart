import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'auth_service.dart';

class RevenueShareSnapshot {
  const RevenueShareSnapshot({
    required this.referralCode,
    required this.shareUrl,
    required this.extraAdsEnabled,
    required this.referredCount,
    required this.pendingKopecks,
    required this.availableKopecks,
    required this.asViewerKopecks,
    required this.asReferrerKopecks,
    this.referredByName,
  });

  final String referralCode;
  final String shareUrl;
  final bool extraAdsEnabled;
  final int referredCount;
  final int pendingKopecks;
  final int availableKopecks;
  final int asViewerKopecks;
  final int asReferrerKopecks;
  final String? referredByName;

  factory RevenueShareSnapshot.fromJson(Map<String, dynamic> json) {
    final referredBy = json['referred_by'];
    return RevenueShareSnapshot(
      referralCode: (json['referral_code'] as String? ?? '').trim(),
      shareUrl: (json['share_url'] as String? ?? '').trim(),
      extraAdsEnabled: json['extra_ads_enabled'] == true,
      referredCount: (json['referred_count'] as num?)?.toInt() ?? 0,
      pendingKopecks: (json['pending_kopecks'] as num?)?.toInt() ?? 0,
      availableKopecks: (json['available_kopecks'] as num?)?.toInt() ?? 0,
      asViewerKopecks: (json['as_viewer_kopecks'] as num?)?.toInt() ?? 0,
      asReferrerKopecks: (json['as_referrer_kopecks'] as num?)?.toInt() ?? 0,
      referredByName: referredBy is Map
          ? referredBy['name'] as String?
          : null,
    );
  }

  String get pendingRub => _rub(pendingKopecks);
  String get availableRub => _rub(availableKopecks);
  String get viewerRub => _rub(asViewerKopecks);
  String get referrerRub => _rub(asReferrerKopecks);

  static String _rub(int kopecks) {
    final rub = kopecks / 100;
    return '${rub.toStringAsFixed(2)} ₽';
  }
}

class RevenueShareApi {
  static String get _base => '${ApiService.baseUrl}/api/v1/revenue-share';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<RevenueShareSnapshot> me() async {
    final response = await http.get(Uri.parse('$_base/me'), headers: await _headers());
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить программу',
      );
    }
    return RevenueShareSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<RevenueShareSnapshot> setExtraAds(bool enabled) async {
    final response = await http.post(
      Uri.parse('$_base/extra-ads'),
      headers: await _headers(),
      body: jsonEncode({'enabled': enabled}),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось сохранить настройку',
      );
    }
    return RevenueShareSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<RevenueShareSnapshot> applyCode(String code) async {
    final response = await http.post(
      Uri.parse('$_base/apply-code'),
      headers: await _headers(),
      body: jsonEncode({'code': code.trim()}),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Код не принят',
      );
    }
    return RevenueShareSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
