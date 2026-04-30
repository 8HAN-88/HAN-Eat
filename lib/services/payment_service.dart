import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'api_service.dart';

/// Сервис для работы с платежами через Stripe
class PaymentService {
  static String get baseUrl => ApiService.baseUrl + '/api/v1';

  /// Создать Stripe Checkout Session
  static Future<CheckoutSessionResponse> createCheckoutSession({
    required String plan, // 'monthly' | 'yearly'
    String? successUrl,
    String? cancelUrl,
  }) async {
    final token = await AuthService.getAccessToken();
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

  /// Получить информацию о ценах подписок
  static Future<SubscriptionPricesResponse> getPrices() async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/payments/prices');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SubscriptionPricesResponse.fromJson(data);
    } else {
      throw Exception('Failed to load subscription prices');
    }
  }

  /// Открыть Stripe Checkout в браузере
  static Future<void> openCheckout(String checkoutUrl) async {
    final uri = Uri.parse(checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication, // Открываем в браузере
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
  final String provider; // "stripe" | "yookassa"
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
  final PriceInfo monthly;
  final PriceInfo yearly;
  final String provider; // "stripe" | "yookassa"
  final String? country;

  SubscriptionPricesResponse({
    required this.monthly,
    required this.yearly,
    required this.provider,
    this.country,
  });

  factory SubscriptionPricesResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionPricesResponse(
      monthly: PriceInfo.fromJson(json['monthly'] as Map<String, dynamic>),
      yearly: PriceInfo.fromJson(json['yearly'] as Map<String, dynamic>),
      provider: json['provider'] as String? ?? 'stripe',
      country: json['country'] as String?,
    );
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
      currency: json['currency'] as String,
      priceId: json['price_id'] as String?,
      interval: json['interval'] as String?,
    );
  }
}

