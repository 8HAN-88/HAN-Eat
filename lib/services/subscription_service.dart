// Сервис для работы с подписками H.A.N. (тарифы AI / Creator / Pro)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'api_service.dart';

class SubscriptionService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';
  
  /// Получить статус подписки
  static Future<SubscriptionStatusResponse> getSubscriptionStatus() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception('Failed to load subscription status');
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
      throw Exception('Not authenticated');
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
      throw Exception(error['detail'] ?? 'Failed to create subscription');
    }
  }
  
  /// Активировать пробный период (ai | pro), без ЮKassa.
  static Future<CreateSubscriptionResponse> startTrial({
    String product = 'ai',
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception(error['detail'] ?? 'Failed to start trial');
    }
  }

  /// Запросить отмену подписки через поддержку
  static Future<CancelSubscriptionResponse> requestCancelSubscription({
    required String cancellationReason,
    String? improvementFeedback,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception(error['detail'] ?? 'Failed to request subscription cancellation');
    }
  }
  
  /// Получить историю подписок
  static Future<SubscriptionHistoryResponse> getSubscriptionHistory() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception('Failed to load subscription history');
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

  bool get hasAnyPaid => isActive && subscriptionType != 'free';

  bool trialEligibleFor(String product) =>
      trialEligible?[product] == true;

  factory SubscriptionStatusResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['entitlements'];
    Map<String, bool> ent = {};
    if (raw is Map<String, dynamic>) {
      for (final e in raw.entries) {
        ent[e.key] = e.value == true;
      }
    }
    final expireRaw = json['subscription_expire_at'] ?? json['expires_at'];
    Map<String, bool>? trialElig;
    final trialRaw = json['trial_eligible'];
    if (trialRaw is Map<String, dynamic>) {
      trialElig = {
        for (final e in trialRaw.entries) e.key: e.value == true,
      };
    }
    return SubscriptionStatusResponse(
      isPlus: json['is_plus'] as bool? ?? false,
      hasAi: json['has_ai'] as bool? ?? false,
      hasCreator: json['has_creator'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      subscriptionStatus: json['subscription_status'] as String? ?? 'active',
      subscription: json['subscription'] != null
          ? SubscriptionData.fromJson(json['subscription'] as Map<String, dynamic>)
          : null,
      subscriptionType: json['subscription_type'] as String? ?? 'free',
      expiresAt: expireRaw != null ? DateTime.parse(expireRaw as String) : null,
      platform: json['platform'] as String?,
      autoRenew: json['auto_renew'] as bool? ?? false,
      entitlements: ent,
      trialEligible: trialElig,
      inGracePeriod: json['in_grace_period'] as bool? ?? false,
      upgradeOptions: (json['upgrade_options'] as List<dynamic>?)
              ?.map((e) => SubscriptionUpgradeOption.fromJson(
                    e as Map<String, dynamic>,
                  ))
              .toList() ??
          const [],
    );
  }
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
    final monthly = (json['monthly_price'] as num?)?.toDouble() ?? 0;
    final full = (json['full_price'] as num?)?.toDouble() ?? monthly;
    final due = (json['amount_due'] as num?)?.toDouble() ?? full;
    return SubscriptionUpgradeOption(
      product: json['product'] as String,
      name: json['name'] as String? ?? json['product'] as String,
      monthlyPrice: monthly,
      reason: json['reason'] as String?,
      fullPrice: full,
      amountDue: due,
      creditRub: (json['credit_rub'] as num?)?.toDouble() ?? 0,
      remainingDays: json['remaining_days'] as int? ?? 0,
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
      id: json['id'] as int,
      plan: json['plan'] as String,
      product: json['product'] as String? ?? 'pro',
      status: json['status'] as String,
      paymentProvider: json['payment_provider'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
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
      subscription: SubscriptionData.fromJson(json['subscription'] as Map<String, dynamic>),
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
      subscriptions: (json['subscriptions'] as List<dynamic>)
          .map((item) => SubscriptionData.fromJson(item as Map<String, dynamic>))
          .toList(),
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
      ticketId: json['ticket_id'] as int,
      message: json['message'] as String,
      note: json['note'] as String,
    );
  }
}

