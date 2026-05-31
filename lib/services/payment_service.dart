import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'api_service.dart';

/// Платежи: YooKassa (RU) / Stripe.
class PaymentService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';

  static Future<CheckoutSessionResponse> createCheckoutSession({
    required String plan,
    required String product,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/checkout');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'plan': plan,
        'product': product,
        if (successUrl != null) 'success_url': successUrl,
        if (cancelUrl != null) 'cancel_url': cancelUrl,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CheckoutSessionResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create checkout session');
    }
  }

  static Future<SubscriptionPricesResponse> getPrices() async {
    final token = await AuthService.getAccessTokenForApi();
    final uri = Uri.parse('$baseUrl/payments/prices');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SubscriptionPricesResponse.fromJson(data);
    } else {
      throw Exception('Failed to load subscription prices');
    }
  }

  static Future<List<PaymentHistoryItem>> getPaymentHistory() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/history');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['payments'] as List<dynamic>? ?? [];
      return list
          .map((e) => PaymentHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load payment history');
  }

  static Future<String?> refreshReceiptUrl(int subscriptionId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/$subscriptionId/receipt');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['receipt_url'] as String?;
    }
    throw Exception('Failed to load receipt');
  }

  static Future<int> requestRefund({
    required int subscriptionId,
    String? reason,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/refund-request');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'subscription_id': subscriptionId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['ticket_id'] as int? ?? 0;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to request refund');
  }

  static Future<void> openReceiptUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not open receipt URL');
    }
  }

  // --- Admin (is_admin) ---

  static Future<List<AdminRefundQueueItem>> getAdminRefundQueue() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/admin/refund-queue');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['items'] as List<dynamic>? ?? [];
      return list
          .map((e) =>
              AdminRefundQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (response.statusCode == 403) {
      throw Exception('Требуются права администратора');
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to load refund queue');
  }

  static Future<void> adminProcessRefund({
    required int subscriptionId,
    double? amount,
    String? reason,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/admin/refund');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'subscription_id': subscriptionId,
        if (amount != null) 'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );

    if (response.statusCode == 200) return;
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to process refund');
  }

  static Future<void> adminRejectRefund({
    required int subscriptionId,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/admin/refund/reject');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'subscription_id': subscriptionId,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    );

    if (response.statusCode == 200) return;
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to reject refund');
  }

  static Future<void> openCheckout(String checkoutUrl) async {
    final uri = Uri.parse(checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      throw Exception('Could not launch checkout URL');
    }
  }
}

class CheckoutSessionResponse {
  final String? sessionId;
  final String? paymentId;
  final String url;
  final String customerEmail;
  final String provider;
  final String currency;

  CheckoutSessionResponse({
    this.sessionId,
    this.paymentId,
    required this.url,
    required this.customerEmail,
    required this.provider,
    this.currency = 'USD',
  });

  factory CheckoutSessionResponse.fromJson(Map<String, dynamic> json) {
    return CheckoutSessionResponse(
      sessionId: json['session_id'] as String?,
      paymentId: json['payment_id'] as String?,
      url: json['url'] as String,
      customerEmail: json['customer_email'] as String,
      provider: json['provider'] as String? ?? 'stripe',
      currency: json['currency'] as String? ?? 'USD',
    );
  }
}

class SubscriptionPricesResponse {
  final String provider;
  final String? country;
  final String currency;
  final int? trialDays;
  final Map<String, SubscriptionTierPrice> tiers;
  final PriceInfo? monthly;
  final PriceInfo? yearly;

  SubscriptionPricesResponse({
    required this.provider,
    this.country,
    this.currency = 'RUB',
    this.trialDays,
    required this.tiers,
    this.monthly,
    this.yearly,
  });

  SubscriptionTierPrice? tier(String id) => tiers[id];

  factory SubscriptionPricesResponse.fromJson(Map<String, dynamic> json) {
    final tiersRaw = json['tiers'] as Map<String, dynamic>?;
    final tiers = <String, SubscriptionTierPrice>{};
    if (tiersRaw != null) {
      for (final e in tiersRaw.entries) {
        tiers[e.key] = SubscriptionTierPrice.fromJson(
          e.key,
          e.value as Map<String, dynamic>,
        );
      }
    }

    PriceInfo? monthly;
    PriceInfo? yearly;
    if (json['monthly'] is Map<String, dynamic>) {
      monthly = PriceInfo.fromJson(json['monthly'] as Map<String, dynamic>);
    }
    if (json['yearly'] is Map<String, dynamic>) {
      yearly = PriceInfo.fromJson(json['yearly'] as Map<String, dynamic>);
    }

    return SubscriptionPricesResponse(
      provider: json['provider'] as String? ?? 'yookassa',
      country: json['country'] as String?,
      currency: json['currency'] as String? ?? 'RUB',
      trialDays: json['trial_days'] as int?,
      tiers: tiers,
      monthly: monthly,
      yearly: yearly,
    );
  }
}

class SubscriptionTierPrice {
  final String id;
  final String name;
  final PriceInfo monthly;
  final bool trialEligible;
  final bool recommended;
  final List<String> benefits;

  SubscriptionTierPrice({
    required this.id,
    required this.name,
    required this.monthly,
    this.trialEligible = false,
    this.recommended = false,
    this.benefits = const [],
  });

  factory SubscriptionTierPrice.fromJson(String id, Map<String, dynamic> json) {
    final monthlyJson = json['monthly'] as Map<String, dynamic>? ?? {};
    final benefitsRaw = json['benefits'] as List<dynamic>?;
    return SubscriptionTierPrice(
      id: id,
      name: json['name'] as String? ?? id,
      monthly: PriceInfo.fromJson(monthlyJson),
      trialEligible: json['trial_eligible'] as bool? ?? false,
      recommended: json['recommended'] as bool? ?? false,
      benefits: benefitsRaw?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

class AdminRefundQueueItem {
  final int id;
  final String productName;
  final double amount;
  final String currency;
  final String refundStatus;
  final int? ticketId;
  final String? userEmail;
  final String? userName;
  final DateTime? createdAt;

  AdminRefundQueueItem({
    required this.id,
    required this.productName,
    required this.amount,
    required this.currency,
    required this.refundStatus,
    this.ticketId,
    this.userEmail,
    this.userName,
    this.createdAt,
  });

  factory AdminRefundQueueItem.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) => s != null ? DateTime.parse(s).toLocal() : null;
    final user = json['user'] as Map<String, dynamic>?;
    return AdminRefundQueueItem(
      id: json['id'] as int,
      productName: json['product_name'] as String? ?? 'Подписка',
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'RUB',
      refundStatus: json['refund_status'] as String? ?? 'requested',
      ticketId: json['ticket_id'] as int?,
      userEmail: user?['email'] as String?,
      userName: user?['name'] as String?,
      createdAt: parse(json['created_at'] as String?),
    );
  }
}

class PaymentHistoryItem {
  final int id;
  final String product;
  final String productName;
  final String plan;
  final String status;
  final double amount;
  final String currency;
  final String? paymentProvider;
  final String? paymentId;
  final String? receiptUrl;
  final String refundStatus;
  final bool canRequestRefund;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  PaymentHistoryItem({
    required this.id,
    required this.product,
    required this.productName,
    required this.plan,
    required this.status,
    required this.amount,
    required this.currency,
    this.paymentProvider,
    this.paymentId,
    this.receiptUrl,
    this.refundStatus = 'none',
    this.canRequestRefund = false,
    this.startedAt,
    this.expiresAt,
    this.createdAt,
  });

  factory PaymentHistoryItem.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) => s != null ? DateTime.parse(s).toLocal() : null;
    return PaymentHistoryItem(
      id: json['id'] as int,
      product: json['product'] as String? ?? 'pro',
      productName: json['product_name'] as String? ?? 'Подписка',
      plan: json['plan'] as String? ?? 'monthly',
      status: json['status'] as String? ?? 'active',
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'RUB',
      paymentProvider: json['payment_provider'] as String?,
      paymentId: json['payment_id'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      refundStatus: json['refund_status'] as String? ?? 'none',
      canRequestRefund: json['can_request_refund'] as bool? ?? false,
      startedAt: parse(json['started_at'] as String?),
      expiresAt: parse(json['expires_at'] as String?),
      createdAt: parse(json['created_at'] as String?),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Активна';
      case 'trial':
        return 'Пробный период';
      case 'cancelled':
        return 'Отменена';
      case 'expired':
        return 'Истекла';
      default:
        return status;
    }
  }

  String get refundStatusLabel {
    switch (refundStatus) {
      case 'requested':
        return 'Возврат в обработке';
      case 'refunded':
        return 'Возврат выполнен';
      case 'rejected':
        return 'Возврат отклонён';
      default:
        return '';
    }
  }
}

class PriceInfo {
  final double price;
  final String currency;
  final String? priceId;
  final String? interval;

  PriceInfo({
    required this.price,
    required this.currency,
    this.priceId,
    this.interval,
  });

  factory PriceInfo.fromJson(Map<String, dynamic> json) {
    return PriceInfo(
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'RUB',
      priceId: json['price_id'] as String?,
      interval: json['interval'] as String?,
    );
  }
}
