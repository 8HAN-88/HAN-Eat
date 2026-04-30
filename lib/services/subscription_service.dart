/// Сервис для работы с подписками H.A.N. Plus
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'api_service.dart';

class SubscriptionService {
  static String get baseUrl => ApiService.baseUrl + '/api/v1';
  
  /// Получить статус подписки
  static Future<SubscriptionStatusResponse> getSubscriptionStatus() async {
    final token = await AuthService.getAccessToken();
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
    final token = await AuthService.getAccessToken();
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
  
  /// Запросить отмену подписки через поддержку
  static Future<CancelSubscriptionResponse> requestCancelSubscription() async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/subscriptions/cancel');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
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
    final token = await AuthService.getAccessToken();
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
  final SubscriptionData? subscription;
  final String subscriptionType;
  final DateTime? expiresAt;
  
  SubscriptionStatusResponse({
    required this.isPlus,
    this.subscription,
    required this.subscriptionType,
    this.expiresAt,
  });
  
  factory SubscriptionStatusResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatusResponse(
      isPlus: json['is_plus'] as bool? ?? false,
      subscription: json['subscription'] != null
          ? SubscriptionData.fromJson(json['subscription'] as Map<String, dynamic>)
          : null,
      subscriptionType: json['subscription_type'] as String? ?? 'free',
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }
}

class SubscriptionData {
  final int id;
  final String plan;
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

