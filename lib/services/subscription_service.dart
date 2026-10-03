// Сервис для работы с подписками HanWe (уровни 9 / 16 / 18)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'api_service.dart';

int _subJsonInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

double _subJsonDouble(Object? raw, [double fallback = 0]) {
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

Map<String, dynamic>? _subJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

class SubscriptionService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';
  
  /// Получить статус подписки
  static Future<SubscriptionStatusResponse> getSubscriptionStatus() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    
    final uri = Uri.parse('$baseUrl/subscriptions/status');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SubscriptionStatusResponse.fromJson(data);
    } else {
      throw Exception('Не удалось загрузить подписку');
    }
  }
  
  /// Создать подписку (после успешной оплаты)
  static Future<CreateSubscriptionResponse> createSubscription({
    required String plan, // 'monthly' | 'yearly'
    required String paymentProvider, // 'stripe' | 'paypal' | 'apple' | 'google'
    required String paymentProviderSubscriptionId,
    required double amount,
    String currency = 'USD',
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    
    final uri = Uri.parse('$baseUrl/subscriptions/create');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'plan': plan,
        'payment_provider': paymentProvider,
        'payment_provider_subscription_id': paymentProviderSubscriptionId,
        'amount': amount,
        'currency': currency,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CreateSubscriptionResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Не удалось оформить подписку');
    }
  }
  
  /// Активировать пробный период (ai | pro), без ЮKassa.
  static Future<CreateSubscriptionResponse> startTrial({
    String product = 'ai',
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }

    final uri = Uri.parse('$baseUrl/subscriptions/trial');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'product': product}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CreateSubscriptionResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Не удалось начать пробный период');
    }
  }

  /// Запросить отмену подписки через поддержку
  static Future<CancelSubscriptionResponse> requestCancelSubscription({
    required String cancellationReason,
    String? improvementFeedback,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    
    final uri = Uri.parse('$baseUrl/subscriptions/cancel');
    final body = <String, dynamic>{
      'cancellation_reason': cancellationReason,
    };
    final feedback = improvementFeedback?.trim();
    if (feedback != null && feedback.isNotEmpty) {
      body['improvement_feedback'] = feedback;
    }
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CancelSubscriptionResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Не удалось отправить запрос на отмену');
    }
  }
  
  /// Получить историю подписок
  static Future<SubscriptionHistoryResponse> getSubscriptionHistory() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    
    final uri = Uri.parse('$baseUrl/subscriptions/history');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SubscriptionHistoryResponse.fromJson(data);
    } else {
      throw Exception('Не удалось загрузить историю подписки');
    }
  }
}

class SubscriptionStatusResponse {
  final bool isPlus;
  final bool hasAi;
  final bool hasCreator;
  final bool isActive;
  final String subscriptionStatus;
  final SubscriptionData? subscription;
  final String subscriptionType;
  final DateTime? expiresAt;
  final String? platform;
  final bool autoRenew;
  final Map<String, bool> entitlements;
  final Map<String, bool>? trialEligible;
  final bool inGracePeriod;
  final List<SubscriptionUpgradeOption> upgradeOptions;

  SubscriptionStatusResponse({
    required this.isPlus,
    this.hasAi = false,
    this.hasCreator = false,
    this.isActive = false,
    this.subscriptionStatus = 'active',
    this.subscription,
    required this.subscriptionType,
    this.expiresAt,
    this.platform,
    this.autoRenew = false,
    this.entitlements = const {},
    this.trialEligible,
    this.inGracePeriod = false,
    this.upgradeOptions = const [],
  });

  bool hasEntitlement(String slug) => entitlements[slug] == true;

  bool get hasAnyPaid =>
      isActive &&
      (subscriptionType != 'free' || entitlements.values.any((v) => v));

  bool get hasPro =>
      hasEntitlement('pro') ||
      hasEntitlement('priority_support') ||
      (isActive && subscriptionType == 'pro');

  bool get canSchedulePosts => hasEntitlement('creator_scheduled_posts');
  bool get canPromotePosts => hasEntitlement('creator_promotion');
  bool get canPinPosts => hasEntitlement('creator_pinned');
  bool get canCreatorAnalytics => hasEntitlement('creator_analytics');
  bool get canCreatorTools => hasEntitlement('creator_tools');
  bool get canAdvancedStats => hasEntitlement('advanced_stats');
  bool get canOfflineSaved => hasEntitlement('offline_saved_posts');
  bool get canAiAssist => hasAi || hasEntitlement('ai_priority_speed');
  bool get hasAdFree => hasEntitlement('ad_free');
  bool get hasPremiumBadge => hasEntitlement('premium_badge');
  bool get hasProfileDecoration => hasEntitlement('profile_decoration');
  bool get hasLargerUploads => hasEntitlement('larger_uploads');
  bool get hasChatTranslation => hasEntitlement('chat_translation');
  bool get hasExtraPins => hasEntitlement('extra_pins');
  bool get hasPrivacyPlus => hasEntitlement('privacy_plus');
  bool get hasGifSearch => hasEntitlement('gif_search');
  bool get hasStoryViewers => hasEntitlement('story_viewers');
  bool get hasScheduledMessages => hasEntitlement('scheduled_messages');
  bool get hasSilentSend => hasEntitlement('silent_send');
  bool get hasLiveLocation => hasEntitlement('live_location');
  bool get hasPremiumStickers => hasEntitlement('premium_stickers');
  bool get hasMessageEffects => hasEntitlement('message_effects');

  bool trialEligibleFor(String product) =>
      trialEligible?[product] == true;

  factory SubscriptionStatusResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['entitlements'];
    Map<String, bool> ent = {};
    if (raw is Map) {
      for (final e in raw.entries) {
        ent['${e.key}'] = e.value == true;
      }
    }
    final expireRaw = json['subscription_expire_at'] ?? json['expires_at'];
    Map<String, bool>? trialElig;
    final trialRaw = json['trial_eligible'];
    if (trialRaw is Map) {
      trialElig = {
        for (final e in trialRaw.entries) '${e.key}': e.value == true,
      };
    }
    return SubscriptionStatusResponse(
      isPlus: json['is_plus'] as bool? ?? false,
      hasAi: json['has_ai'] as bool? ?? false,
      hasCreator: json['has_creator'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      subscriptionStatus: json['subscription_status'] as String? ?? 'active',
      subscription: _subJsonMap(json['subscription']) != null
          ? SubscriptionData.fromJson(_subJsonMap(json['subscription'])!)
          : null,
      subscriptionType: json['subscription_type'] as String? ?? 'free',
      expiresAt: DateTime.tryParse('$expireRaw'),
      platform: json['platform'] as String?,
      autoRenew: json['auto_renew'] as bool? ?? false,
      entitlements: ent,
      trialEligible: trialElig,
      inGracePeriod: json['in_grace_period'] as bool? ?? false,
      upgradeOptions: [
        for (final raw in (json['upgrade_options'] as List<dynamic>? ?? const []))
          if (_subJsonMap(raw) != null)
            SubscriptionUpgradeOption.fromJson(_subJsonMap(raw)!),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'is_plus': isPlus,
        'has_ai': hasAi,
        'has_creator': hasCreator,
        'is_active': isActive,
        'subscription_status': subscriptionStatus,
        'subscription_type': subscriptionType,
        if (expiresAt != null)
          'expires_at': expiresAt!.toIso8601String(),
        if (platform != null) 'platform': platform,
        'auto_renew': autoRenew,
        'entitlements': entitlements,
        if (trialEligible != null) 'trial_eligible': trialEligible,
        'in_grace_period': inGracePeriod,
      };
}

class SubscriptionUpgradeOption {
  final String product;
  final String name;
  final double monthlyPrice;
  final String? reason;
  final double fullPrice;
  final double amountDue;
  final double creditRub;
  final int remainingDays;
  final bool isUpgrade;

  SubscriptionUpgradeOption({
    required this.product,
    required this.name,
    required this.monthlyPrice,
    this.reason,
    this.fullPrice = 0,
    this.amountDue = 0,
    this.creditRub = 0,
    this.remainingDays = 0,
    this.isUpgrade = false,
  });

  factory SubscriptionUpgradeOption.fromJson(Map<String, dynamic> json) {
    final monthly = _subJsonDouble(json['monthly_price']);
    final full = _subJsonDouble(json['full_price'], monthly);
    final due = _subJsonDouble(json['amount_due'], full);
    return SubscriptionUpgradeOption(
      product: json['product'] as String? ?? '',
      name: json['name'] as String? ?? json['product'] as String? ?? '',
      monthlyPrice: monthly,
      reason: json['reason'] as String?,
      fullPrice: full,
      amountDue: due,
      creditRub: _subJsonDouble(json['credit_rub']),
      remainingDays: _subJsonInt(json['remaining_days']),
      isUpgrade: json['is_upgrade'] as bool? ?? false,
    );
  }
}

class SubscriptionData {
  final int id;
  final String plan;
  final String product;
  final String status;
  final String? paymentProvider;
  final double amount;
  final String currency;
  final DateTime startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  
  SubscriptionData({
    required this.id,
    required this.plan,
    this.product = 'pro',
    required this.status,
    this.paymentProvider,
    required this.amount,
    required this.currency,
    required this.startedAt,
    this.expiresAt,
    required this.autoRenew,
  });
  
  factory SubscriptionData.fromJson(Map<String, dynamic> json) {
    return SubscriptionData(
      id: _subJsonInt(json['id']),
      plan: json['plan'] as String? ?? '',
      product: json['product'] as String? ?? 'pro',
      status: json['status'] as String? ?? '',
      paymentProvider: json['payment_provider'] as String?,
      amount: _subJsonDouble(json['amount']),
      currency: json['currency'] as String? ?? 'RUB',
      startedAt: DateTime.tryParse('${json['started_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: DateTime.tryParse('${json['expires_at'] ?? ''}'),
      autoRenew: json['auto_renew'] as bool? ?? true,
    );
  }
}

class CreateSubscriptionResponse {
  final bool success;
  final SubscriptionData subscription;
  final String message;
  
  CreateSubscriptionResponse({
    required this.success,
    required this.subscription,
    required this.message,
  });
  
  factory CreateSubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return CreateSubscriptionResponse(
      success: json['success'] as bool,
      subscription: SubscriptionData.fromJson(
        _subJsonMap(json['subscription']) ?? const {},
      ),
      message: json['message'] as String,
    );
  }
}

class SubscriptionHistoryResponse {
  final List<SubscriptionData> subscriptions;
  
  SubscriptionHistoryResponse({
    required this.subscriptions,
  });
  
  factory SubscriptionHistoryResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistoryResponse(
      subscriptions: [
        for (final item in (json['subscriptions'] as List<dynamic>? ?? const []))
          if (_subJsonMap(item) != null)
            SubscriptionData.fromJson(_subJsonMap(item)!),
      ],
    );
  }
}

class CancelSubscriptionResponse {
  final bool success;
  final int ticketId;
  final String message;
  final String note;
  
  CancelSubscriptionResponse({
    required this.success,
    required this.ticketId,
    required this.message,
    required this.note,
  });
  
  factory CancelSubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return CancelSubscriptionResponse(
      success: json['success'] as bool,
      ticketId: _subJsonInt(json['ticket_id']),
      message: json['message'] as String,
      note: json['note'] as String,
    );
  }
}

