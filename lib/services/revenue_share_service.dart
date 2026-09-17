import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/referral/pending_referral.dart';
import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'app_invite_service.dart';
import 'auth_service.dart';
import 'pending_referral_store.dart';

class PartnerPayout {
  const PartnerPayout({
    required this.id,
    required this.userId,
    required this.kind,
    required this.amountKopecks,
    required this.amountStars,
    required this.status,
    this.phone,
    this.recipientName,
    this.note,
    this.createdAt,
    this.reviewedAt,
    this.paidAt,
    this.userName,
    this.userEmail,
    this.userUsername,
  });

  final int id;
  final int userId;
  final String kind;
  final int amountKopecks;
  final int amountStars;
  final String status;
  final String? phone;
  final String? recipientName;
  final String? note;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final DateTime? paidAt;
  final String? userName;
  final String? userEmail;
  final String? userUsername;

  factory PartnerPayout.fromJson(Map<String, dynamic> json) {
    return PartnerPayout(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String? ?? '').trim(),
      amountKopecks: (json['amount_kopecks'] as num?)?.toInt() ?? 0,
      amountStars: (json['amount_stars'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String? ?? '').trim(),
      phone: (json['phone'] as String?)?.trim(),
      recipientName: (json['recipient_name'] as String?)?.trim(),
      note: (json['note'] as String?)?.trim(),
      createdAt: _parseTime(json['created_at']),
      reviewedAt: _parseTime(json['reviewed_at']),
      paidAt: _parseTime(json['paid_at']),
      userName: (json['user_name'] as String?)?.trim(),
      userEmail: (json['user_email'] as String?)?.trim(),
      userUsername: (json['user_username'] as String?)?.trim(),
    );
  }

  String get amountRub => RevenueShareSnapshot.rub(amountKopecks);

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'В обработке';
      case 'paid':
        return 'Выплачено';
      case 'rejected':
        return 'Отклонено';
      default:
        return status;
    }
  }

  String get kindLabel => kind == 'stars' ? 'В звёзды' : 'На карту / СБП';

  static DateTime? _parseTime(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class RevenueShareSnapshot {
  const RevenueShareSnapshot({
    required this.referralCode,
    required this.shareUrl,
    required this.extraAdsEnabled,
    required this.referredCount,
    required this.pendingKopecks,
    required this.availableKopecks,
    required this.payoutHoldKopecks,
    required this.paidKopecks,
    required this.asViewerKopecks,
    required this.asReferrerKopecks,
    required this.kopecksPerStar,
    required this.minCardKopecks,
    required this.convertibleStars,
    required this.payouts,
    this.referredByName,
    this.referredByCode,
    this.referredByUsername,
    this.referredById,
    this.lastPayout,
  });

  final String referralCode;
  final String shareUrl;
  final bool extraAdsEnabled;
  final int referredCount;
  final int pendingKopecks;
  final int availableKopecks;
  final int payoutHoldKopecks;
  final int paidKopecks;
  final int asViewerKopecks;
  final int asReferrerKopecks;
  final int kopecksPerStar;
  final int minCardKopecks;
  final int convertibleStars;
  final List<PartnerPayout> payouts;
  final String? referredByName;
  final String? referredByCode;
  final String? referredByUsername;
  final int? referredById;
  final PartnerPayout? lastPayout;

  factory RevenueShareSnapshot.fromJson(Map<String, dynamic> json) {
    final referredBy = json['referred_by'];
    final referredMap = referredBy is Map ? referredBy : null;
    final payoutsRaw = json['payouts'];
    final last = json['last_payout'];
    return RevenueShareSnapshot(
      referralCode: (json['referral_code'] as String? ?? '').trim(),
      shareUrl: (json['share_url'] as String? ?? '').trim(),
      extraAdsEnabled: json['extra_ads_enabled'] == true,
      referredCount: (json['referred_count'] as num?)?.toInt() ?? 0,
      pendingKopecks: (json['pending_kopecks'] as num?)?.toInt() ?? 0,
      availableKopecks: (json['available_kopecks'] as num?)?.toInt() ?? 0,
      payoutHoldKopecks: (json['payout_hold_kopecks'] as num?)?.toInt() ?? 0,
      paidKopecks: (json['paid_kopecks'] as num?)?.toInt() ?? 0,
      asViewerKopecks: (json['as_viewer_kopecks'] as num?)?.toInt() ?? 0,
      asReferrerKopecks: (json['as_referrer_kopecks'] as num?)?.toInt() ?? 0,
      kopecksPerStar: (json['kopecks_per_star'] as num?)?.toInt() ?? 80,
      minCardKopecks: (json['min_card_kopecks'] as num?)?.toInt() ?? 50000,
      convertibleStars: (json['convertible_stars'] as num?)?.toInt() ?? 0,
      payouts: payoutsRaw is List
          ? payoutsRaw
              .whereType<Map>()
              .map((row) => PartnerPayout.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
      referredByName: referredMap?['name'] as String?,
      referredByCode: (referredMap?['code'] as String?)?.trim(),
      referredByUsername: (referredMap?['username'] as String?)?.trim(),
      referredById: (referredMap?['id'] as num?)?.toInt(),
      lastPayout: last is Map
          ? PartnerPayout.fromJson(Map<String, dynamic>.from(last))
          : null,
    );
  }

  String get pendingRub => rub(pendingKopecks);
  String get availableRub => rub(availableKopecks);
  String get payoutHoldRub => rub(payoutHoldKopecks);
  String get paidRub => rub(paidKopecks);
  String get viewerRub => rub(asViewerKopecks);
  String get referrerRub => rub(asReferrerKopecks);

  bool get canConvertStars => convertibleStars > 0;
  bool get canRequestCard => availableKopecks >= minCardKopecks;

  static String rub(int kopecks) {
    final value = kopecks / 100;
    return '${value.toStringAsFixed(2)} ₽';
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
    return _cache(_decode(response.body));
  }

  static RevenueShareSnapshot _decode(String body) {
    return RevenueShareSnapshot.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
  }

  static RevenueShareSnapshot _cache(RevenueShareSnapshot snap) {
    if (snap.referralCode.isNotEmpty) {
      AppInviteService.rememberOfficialCode(snap.referralCode);
      unawaited(PendingReferralStore.rememberOfficial(snap.referralCode));
    }
    return snap;
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
    return _cache(_decode(response.body));
  }

  static Future<RevenueShareSnapshot> applyCode(String code) async {
    final extracted = PendingReferral.extract(code) ?? code.trim();
    final response = await http.post(
      Uri.parse('$_base/apply-code'),
      headers: await _headers(),
      body: jsonEncode({'code': extracted}),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Код не принят',
      );
    }
    final snap = _cache(_decode(response.body));
    if (PendingReferral.boundTo(
      extracted,
      referredByCode: snap.referredByCode,
      referredByUsername: snap.referredByUsername,
      referredById: snap.referredById,
    )) {
      unawaited(PendingReferralStore.clear());
    }
    return snap;
  }

  static Future<RevenueShareSnapshot> convertToStars({int? amountKopecks}) async {
    final response = await http.post(
      Uri.parse('$_base/payouts/stars'),
      headers: await _headers(),
      body: jsonEncode({
        if (amountKopecks != null) 'amount_kopecks': amountKopecks,
      }),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось зачислить звёзды',
      );
    }
    return _cache(_decode(response.body));
  }

  static Future<RevenueShareSnapshot> requestCardPayout({
    int? amountKopecks,
    required String phone,
    required String recipientName,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/payouts/card'),
      headers: await _headers(),
      body: jsonEncode({
        if (amountKopecks != null) 'amount_kopecks': amountKopecks,
        'phone': phone,
        'recipient_name': recipientName,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось создать заявку',
      );
    }
    return _cache(_decode(response.body));
  }

  static Future<List<PartnerPayout>> adminQueue({String status = 'pending'}) async {
    final response = await http.get(
      Uri.parse('$_base/payouts/queue?status=$status'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить очередь',
      );
    }
    final raw = jsonDecode(response.body);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => PartnerPayout.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<PartnerPayout> reviewPayout({
    required int payoutId,
    required bool approve,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/payouts/$payoutId/review'),
      headers: await _headers(),
      body: jsonEncode({
        'approve': approve,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );
    if (response.statusCode != 200) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось разобрать заявку',
      );
    }
    return PartnerPayout.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
